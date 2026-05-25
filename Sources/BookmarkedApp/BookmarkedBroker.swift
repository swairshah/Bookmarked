import Foundation
import Network
import BookmarkedClient

final class BookmarkedBroker {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "bookmarked.broker")
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let store: BookmarkStore

    init(port: Int, store: BookmarkStore) throws {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            throw NSError(domain: "Bookmarked", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid broker port: \(port)"])
        }

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        listener = try NWListener(using: params, on: nwPort)
        self.store = store

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func start() {
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection: connection)
        }
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                NSLog("Bookmarked broker: listening on 127.0.0.1:\(BookmarkedDefaults.brokerPort)")
            case .failed(let error):
                NSLog("Bookmarked broker: failed: \(error)")
            default:
                break
            }
        }
        listener.start(queue: queue)
    }

    func stop() {
        listener.newConnectionHandler = nil
        listener.cancel()
    }

    private func handle(connection: NWConnection) {
        if !Self.isLoopback(endpoint: connection.endpoint) {
            NSLog("Bookmarked broker: rejecting non-loopback connection from \(connection.endpoint)")
            connection.cancel()
            return
        }
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private static func isLoopback(endpoint: NWEndpoint) -> Bool {
        switch endpoint {
        case .hostPort(let host, _):
            switch host {
            case .ipv4(let address):
                return address.rawValue.first == 127 || address == .loopback
            case .ipv6(let address):
                if address == .loopback { return true }
                let bytes = address.rawValue
                if bytes.count == 16 {
                    let mappedPrefix = bytes.prefix(12) == Data([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xff, 0xff])
                    let v4First = bytes[bytes.index(bytes.startIndex, offsetBy: 12)]
                    return mappedPrefix && v4First == 127
                }
                return false
            case .name(let name, _):
                return name == "localhost" || name == "127.0.0.1" || name == "::1"
            @unknown default:
                return false
            }
        default:
            return false
        }
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 512 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            if let error {
                self.send(.failure("Connection error: \(error.localizedDescription)"), on: connection)
                return
            }

            var nextBuffer = buffer
            if let data { nextBuffer.append(data) }

            if let newline = nextBuffer.firstIndex(of: 0x0A) {
                self.handleLine(nextBuffer.subdata(in: 0..<newline), on: connection)
                return
            }
            if isComplete {
                self.handleLine(nextBuffer, on: connection)
                return
            }
            self.receive(on: connection, buffer: nextBuffer)
        }
    }

    private func handleLine(_ line: Data, on connection: NWConnection) {
        guard !line.isEmpty else {
            send(.failure("Empty request"), on: connection)
            return
        }

        let request: BookmarkedRequest
        do {
            request = try decoder.decode(BookmarkedRequest.self, from: line)
        } catch {
            send(.failure("Invalid JSON: \(error.localizedDescription)"), on: connection)
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.send(self.dispatch(request: request), on: connection)
        }
    }

    @MainActor
    private func dispatch(request: BookmarkedRequest) -> BookmarkedResponse {
        switch request.type {
        case "health":
            return .success(count: store.items.count)

        case "list", "search":
            var items = store.search(request.query ?? "")
            if let kind = request.kind?.trimmingCharacters(in: .whitespacesAndNewlines), !kind.isEmpty {
                items = items.filter { $0.kind.matchesCLIValue(kind) }
            }
            if let tag = request.tag?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !tag.isEmpty {
                items = items.filter { item in
                    item.tags.contains { $0.lowercased() == tag }
                }
            }
            if let limit = request.limit, limit >= 0 {
                items = Array(items.prefix(limit))
            }
            return .success(items: items.map { $0.clientBookmark(includeContent: false) }, count: items.count)

        case "get":
            guard let item = resolveItem(request: request) else {
                return .failure("Bookmark not found")
            }
            return .success(item: item.clientBookmark(includeContent: false))

        case "read":
            guard let item = resolveItem(request: request) else {
                return .failure("Bookmark not found")
            }
            let format = request.format ?? "text"
            let content: String
            switch format {
            case "note", "notes":
                content = item.note ?? ""
            case "html":
                content = item.readerHTML ?? ""
            case "summary":
                content = item.summary ?? ""
            case "url":
                content = item.url?.absoluteString ?? item.fileURL?.path ?? ""
            default:
                content = item.contentText
            }
            return .success(item: item.clientBookmark(includeContent: false), content: content)

        case "note", "append-note", "add-note":
            guard let item = resolveItem(request: request) else {
                return .failure("Bookmark not found")
            }
            guard let note = request.note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .failure("Missing note text")
            }
            guard let updated = store.appendNote(id: item.id, text: note) else {
                return .failure("Could not append note")
            }
            return .success(item: updated.clientBookmark(includeContent: false))

        case "tag":
            guard let item = resolveItem(request: request) else {
                return .failure("Bookmark not found")
            }
            guard let tag = request.tag, !tag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .failure("Missing tag")
            }
            let action = request.tagAction ?? "add"
            let updated: BookmarkItem?
            switch action {
            case "rm", "remove", "delete":
                updated = store.removeTag(id: item.id, tag: tag)
            case "set":
                updated = store.setTags(id: item.id, tags: tag.split(separator: ",").map(String.init))
            default:
                updated = store.addTag(id: item.id, tag: tag)
            }
            guard let updated else {
                return .failure("Could not update tags")
            }
            return .success(item: updated.clientBookmark(includeContent: false), tags: updated.tags)

        default:
            return .failure("Unknown command: \(request.type)")
        }
    }

    @MainActor
    private func resolveItem(request: BookmarkedRequest) -> BookmarkItem? {
        guard let value = request.id ?? request.idPrefix else { return nil }
        return store.resolveItem(idOrPrefix: value)
    }

    private func send(_ response: BookmarkedResponse, on connection: NWConnection) {
        do {
            var data = try encoder.encode(response)
            data.append(0x0A)
            connection.send(content: data, completion: .contentProcessed { _ in
                connection.cancel()
            })
        } catch {
            connection.cancel()
        }
    }
}

private extension BookmarkKind {
    func matchesCLIValue(_ value: String) -> Bool {
        let normalized = value.lowercased().replacingOccurrences(of: "-", with: "").replacingOccurrences(of: " ", with: "")
        let raw = rawValue.lowercased().replacingOccurrences(of: "-", with: "").replacingOccurrences(of: " ", with: "")
        return normalized == raw || normalized == String(describing: self).lowercased()
    }
}

private extension BookmarkItem {
    func clientBookmark(includeContent: Bool) -> BookmarkedBookmark {
        BookmarkedBookmark(
            id: id,
            title: title,
            kind: kind.rawValue,
            url: url?.absoluteString,
            fileURL: fileURL?.path,
            creator: creator,
            sourceApp: sourceApp,
            summary: summary,
            note: note,
            contentText: includeContent ? contentText : nil,
            readerHTML: includeContent ? readerHTML : nil,
            tags: tags,
            createdAt: createdAt,
            updatedAt: updatedAt,
            lastOpenedAt: lastOpenedAt
        )
    }
}
