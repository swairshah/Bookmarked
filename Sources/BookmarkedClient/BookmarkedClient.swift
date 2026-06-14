import Foundation
import Network

public struct BookmarkedBookmark: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var kind: String
    public var url: String?
    public var fileURL: String?
    public var appLink: String?
    public var creator: String?
    public var sourceApp: String?
    public var summary: String?
    public var note: String?
    public var contentText: String?
    public var readerHTML: String?
    public var tags: [String]
    public var createdAt: Date
    public var updatedAt: Date
    public var lastOpenedAt: Date?

    public init(
        id: UUID,
        title: String,
        kind: String,
        url: String? = nil,
        fileURL: String? = nil,
        appLink: String? = nil,
        creator: String? = nil,
        sourceApp: String? = nil,
        summary: String? = nil,
        note: String? = nil,
        contentText: String? = nil,
        readerHTML: String? = nil,
        tags: [String],
        createdAt: Date,
        updatedAt: Date,
        lastOpenedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.url = url
        self.fileURL = fileURL
        self.appLink = appLink ?? BookmarkedLinks.appLink(for: id)
        self.creator = creator
        self.sourceApp = sourceApp
        self.summary = summary
        self.note = note
        self.contentText = contentText
        self.readerHTML = readerHTML
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastOpenedAt = lastOpenedAt
    }
}

public struct BookmarkedRequest: Codable, Sendable {
    public var type: String
    public var id: String?
    public var idPrefix: String?
    public var query: String?
    public var kind: String?
    public var tag: String?
    public var limit: Int?
    public var note: String?
    public var format: String?
    public var tagAction: String?

    public init(
        type: String,
        id: String? = nil,
        idPrefix: String? = nil,
        query: String? = nil,
        kind: String? = nil,
        tag: String? = nil,
        limit: Int? = nil,
        note: String? = nil,
        format: String? = nil,
        tagAction: String? = nil
    ) {
        self.type = type
        self.id = id
        self.idPrefix = idPrefix
        self.query = query
        self.kind = kind
        self.tag = tag
        self.limit = limit
        self.note = note
        self.format = format
        self.tagAction = tagAction
    }
}

public struct BookmarkedResponse: Codable, Sendable {
    public var ok: Bool
    public var error: String?
    public var item: BookmarkedBookmark?
    public var items: [BookmarkedBookmark]?
    public var count: Int?
    public var content: String?
    public var tags: [String]?

    public init(
        ok: Bool,
        error: String? = nil,
        item: BookmarkedBookmark? = nil,
        items: [BookmarkedBookmark]? = nil,
        count: Int? = nil,
        content: String? = nil,
        tags: [String]? = nil
    ) {
        self.ok = ok
        self.error = error
        self.item = item
        self.items = items
        self.count = count
        self.content = content
        self.tags = tags
    }

    public static func success(
        item: BookmarkedBookmark? = nil,
        items: [BookmarkedBookmark]? = nil,
        count: Int? = nil,
        content: String? = nil,
        tags: [String]? = nil
    ) -> BookmarkedResponse {
        BookmarkedResponse(ok: true, item: item, items: items, count: count, content: content, tags: tags)
    }

    public static func failure(_ message: String) -> BookmarkedResponse {
        BookmarkedResponse(ok: false, error: message)
    }

    public func withResolvedAppLinks() -> BookmarkedResponse {
        var response = self
        response.item = response.item?.withResolvedAppLink()
        response.items = response.items?.map { $0.withResolvedAppLink() }
        return response
    }
}

public enum BookmarkedError: Error, LocalizedError {
    case serverNotRunning
    case invalidResponse
    case serverError(String)

    public var errorDescription: String? {
        switch self {
        case .serverNotRunning:
            return "Bookmarked app is not running. Launch Bookmarked.app first."
        case .invalidResponse:
            return "Invalid response from Bookmarked broker."
        case .serverError(let message):
            return message
        }
    }
}

public enum BookmarkedDefaults {
    public static let brokerHost = "127.0.0.1"
    public static let brokerPort = 27183
}

public enum BookmarkedLinks {
    public static let appScheme = "bookmarked"

    public static func appLink(for id: UUID) -> String {
        "\(appScheme)://open/\(id.uuidString)"
    }
}

public final class BookmarkedClient: @unchecked Sendable {
    public let host: String
    public let port: Int

    public init(host: String = BookmarkedDefaults.brokerHost, port: Int = BookmarkedDefaults.brokerPort) {
        self.host = host
        self.port = port
    }

    public func send(_ request: BookmarkedRequest, timeout: TimeInterval = 3.0) async throws -> BookmarkedResponse {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            throw BookmarkedError.serverError("Invalid port: \(port)")
        }

        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)

        return try await withCheckedThrowingContinuation { continuation in
            let queue = DispatchQueue(label: "bookmarked.client.\(UUID().uuidString)")
            var resumed = false
            var buffer = Data()

            let timeoutWork = DispatchWorkItem {
                if resumed { return }
                resumed = true
                connection.cancel()
                continuation.resume(throwing: BookmarkedError.serverNotRunning)
            }

            func resolve(_ result: Result<BookmarkedResponse, Error>) {
                if resumed { return }
                resumed = true
                timeoutWork.cancel()
                connection.cancel()
                continuation.resume(with: result)
            }

            func parseResponse(_ data: Data) {
                guard !data.isEmpty else {
                    resolve(.failure(BookmarkedError.invalidResponse))
                    return
                }
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                do {
                    resolve(.success(try decoder.decode(BookmarkedResponse.self, from: data)))
                } catch {
                    resolve(.failure(BookmarkedError.invalidResponse))
                }
            }

            func receiveResponse() {
                connection.receive(minimumIncompleteLength: 1, maximumLength: 512 * 1024) { data, _, isComplete, error in
                    if let error {
                        resolve(.failure(error))
                        return
                    }
                    if let data, !data.isEmpty {
                        buffer.append(data)
                        if let nl = buffer.firstIndex(of: 0x0A) {
                            parseResponse(Data(buffer.prefix(upTo: nl)))
                            return
                        }
                    }
                    if isComplete {
                        parseResponse(buffer)
                    } else {
                        receiveResponse()
                    }
                }
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    do {
                        let encoder = JSONEncoder()
                        encoder.dateEncodingStrategy = .iso8601
                        var payload = try encoder.encode(request)
                        payload.append(0x0A)
                        connection.send(content: payload, completion: .contentProcessed { error in
                            if let error {
                                resolve(.failure(error))
                                return
                            }
                            receiveResponse()
                        })
                    } catch {
                        resolve(.failure(error))
                    }
                case .failed(let error):
                    resolve(.failure(error))
                case .cancelled:
                    break
                default:
                    break
                }
            }

            queue.asyncAfter(deadline: .now() + timeout, execute: timeoutWork)
            connection.start(queue: queue)
        }
    }

    public func health() async throws -> Bool {
        try await send(BookmarkedRequest(type: "health")).ok
    }
}

public extension BookmarkedBookmark {
    var shortId: String {
        String(id.uuidString.prefix(8))
    }

    var resolvedAppLink: String {
        appLink ?? BookmarkedLinks.appLink(for: id)
    }

    func withResolvedAppLink() -> BookmarkedBookmark {
        var bookmark = self
        bookmark.appLink = resolvedAppLink
        return bookmark
    }
}
