import Foundation
import BookmarkedClient

let USAGE = """
bookmarked - Bookmarked library CLI

USAGE:
    bookmarked <COMMAND> [ARGS...]
    echo "markdown note" | bookmarked note <id>

COMMANDS:
    search [query]              Search bookmarks
        --kind <kind>           Filter by kind, e.g. webPage, GitHub Repo, note
        --tag <tag>             Filter by tag
        --limit <N>             Limit result count

    list                        List recent bookmarks
        --kind <kind>           Filter by kind
        --tag <tag>             Filter by tag
        --limit <N>             Limit result count

    get <id>                    Show bookmark metadata
    link <id>                   Print title, web/file link, and app link
    read <id>                   Print indexed reader text
        --format <format>       text, html, note, summary, or url

    note <id> <text>            Append markdown notes to a bookmark
                                Also accepts stdin or --note <text>
    tag <id> add <tag>          Add a tag
    tag <id> rm <tag>           Remove a tag
    tag <id> set <a,b,c>        Replace tags with a comma-separated list
    health                      Check whether Bookmarked.app is reachable

GLOBAL OPTIONS:
    --host <HOST>               Broker host (default: 127.0.0.1)
    --port <PORT>               Broker port (default: \(BookmarkedDefaults.brokerPort))
    --links                     Include web/file and app links in text output
    --json                      Output machine-readable JSON
    -q, --quiet                 Suppress non-error output
    -h, --help                  Show this help

IDs can be either a full UUID or a short prefix.
search/get --json include appLink. Agents should return title, url or fileURL, and appLink.
"""

struct ParsedArgs {
    var command = ""
    var positionals: [String] = []
    var host = BookmarkedDefaults.brokerHost
    var port = BookmarkedDefaults.brokerPort
    var query: String?
    var kind: String?
    var tag: String?
    var limit: Int?
    var note: String?
    var format: String?
    var json = false
    var links = false
    var quiet = false
    var help = false
}

func parseArgs() -> ParsedArgs {
    var parsed = ParsedArgs()
    let args = Array(CommandLine.arguments.dropFirst())
    guard !args.isEmpty else {
        parsed.help = true
        return parsed
    }

    var i = 0
    while i < args.count, args[i].hasPrefix("-") {
        if args[i] == "-h" || args[i] == "--help" {
            parsed.help = true
            return parsed
        }
        i += 1
    }
    if i < args.count {
        parsed.command = args[i]
        i += 1
    }

    while i < args.count {
        let arg = args[i]
        switch arg {
        case "-h", "--help":
            parsed.help = true
        case "--host":
            i += 1
            if i < args.count { parsed.host = args[i] }
        case "--port":
            i += 1
            if i < args.count, let value = Int(args[i]) { parsed.port = value }
        case "--query", "-s":
            i += 1
            if i < args.count { parsed.query = args[i] }
        case "--kind":
            i += 1
            if i < args.count { parsed.kind = args[i] }
        case "--tag":
            i += 1
            if i < args.count { parsed.tag = args[i] }
        case "--limit":
            i += 1
            if i < args.count { parsed.limit = Int(args[i]) }
        case "--note", "-n":
            i += 1
            if i < args.count { parsed.note = expandEscapes(args[i]) }
        case "--format", "-f":
            i += 1
            if i < args.count { parsed.format = args[i] }
        case "--json":
            parsed.json = true
        case "--links":
            parsed.links = true
        case "-q", "--quiet":
            parsed.quiet = true
        default:
            if arg.hasPrefix("-") {
                FileHandle.standardError.write("bookmarked: unknown option \(arg)\n".data(using: .utf8)!)
            } else {
                parsed.positionals.append(arg)
            }
        }
        i += 1
    }

    return parsed
}

func expandEscapes(_ value: String) -> String {
    guard value.contains("\\") else { return value }
    let placeholder = "\u{0000}BACKSLASH\u{0000}"
    return value
        .replacingOccurrences(of: "\\\\", with: placeholder)
        .replacingOccurrences(of: "\\n", with: "\n")
        .replacingOccurrences(of: "\\t", with: "\t")
        .replacingOccurrences(of: "\\r", with: "\r")
        .replacingOccurrences(of: placeholder, with: "\\")
}

func readStdin() -> String? {
    if isatty(STDIN_FILENO) != 0 { return nil }
    guard let data = try? FileHandle.standardInput.readToEnd(),
          let value = String(data: data, encoding: .utf8) else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

func die(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write("bookmarked: \(message)\n".data(using: .utf8)!)
    exit(code)
}

func printJSON<T: Encodable>(_ value: T) {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let data = try? encoder.encode(value), let output = String(data: data, encoding: .utf8) {
        print(output)
    }
}

func printRow(index: Int?, item: BookmarkedBookmark, includeLinks: Bool = false) {
    let indexText = index.map { String(format: "%2d ", $0) } ?? ""
    var suffix = ""
    if !includeLinks, let url = item.url ?? item.fileURL, !url.isEmpty {
        suffix += "  \(url)"
    }
    if !item.tags.isEmpty {
        suffix += "  [\(item.tags.joined(separator: ", "))]"
    }
    print("\(indexText)\(item.shortId)  \(item.title)  \(item.kind)\(suffix)")
    if includeLinks {
        printLinks(item: item, indented: true)
    }
}

func printLinks(item: BookmarkedBookmark, indented: Bool = false) {
    let prefix = indented ? "     " : ""
    if !indented {
        print(item.title)
    }
    if let url = item.url, !url.isEmpty {
        print("\(prefix)web: \(url)")
    } else if let fileURL = item.fileURL, !fileURL.isEmpty {
        print("\(prefix)file: \(fileURL)")
    }
    print("\(prefix)app: \(item.resolvedAppLink)")
}

func run() async {
    let args = parseArgs()
    if args.help || args.command.isEmpty {
        FileHandle.standardError.write(USAGE.data(using: .utf8)!)
        exit(args.help ? 0 : 1)
    }

    let client = BookmarkedClient(host: args.host, port: args.port)

    func send(_ request: BookmarkedRequest) async -> BookmarkedResponse {
        do {
            return try await client.send(request)
        } catch {
            die("Could not reach Bookmarked broker on \(args.host):\(args.port). Is Bookmarked.app running?")
        }
    }

    switch args.command {
    case "health", "ping":
        do {
            let ok = try await client.health()
            if ok {
                if !args.quiet { print("ok") }
                exit(0)
            }
            die("broker reported not ok", code: 2)
        } catch {
            die("broker unreachable: \(error.localizedDescription)", code: 2)
        }

    case "list", "ls", "search":
        var query = args.query
        if args.command == "search", query == nil {
            query = args.positionals.joined(separator: " ")
        }
        let response = await send(BookmarkedRequest(
            type: "search",
            query: query,
            kind: args.kind,
            tag: args.tag,
            limit: args.limit
        ))
        if !response.ok { die(response.error ?? "search failed") }
        if args.json {
            printJSON(response.withResolvedAppLinks())
        } else {
            let items = response.items ?? []
            if items.isEmpty {
                if !args.quiet { print("no bookmarks") }
            } else {
                for (index, item) in items.enumerated() {
                    printRow(index: index, item: item, includeLinks: args.links)
                }
            }
        }

    case "get", "show":
        guard let id = args.positionals.first else { die("get requires an id") }
        let response = await send(BookmarkedRequest(type: "get", id: id, idPrefix: id))
        if !response.ok { die(response.error ?? "get failed") }
        if args.json {
            printJSON(response.withResolvedAppLinks())
        } else if let item = response.item {
            printRow(index: nil, item: item, includeLinks: args.links)
            print("  id:       \(item.id.uuidString)")
            if let creator = item.creator { print("  creator:  \(creator)") }
            if let summary = item.summary { print("  summary:  \(summary)") }
            if let note = item.note, !note.isEmpty { print("  note:     \(note)") }
            print("  created:  \(item.createdAt)")
            print("  updated:  \(item.updatedAt)")
        }

    case "link", "links":
        guard let id = args.positionals.first else { die("link requires an id") }
        let response = await send(BookmarkedRequest(type: "get", id: id, idPrefix: id))
        if !response.ok { die(response.error ?? "link failed") }
        if args.json {
            printJSON(response.withResolvedAppLinks())
        } else if let item = response.item {
            printLinks(item: item)
        }

    case "read":
        guard let id = args.positionals.first else { die("read requires an id") }
        let response = await send(BookmarkedRequest(type: "read", id: id, idPrefix: id, format: args.format))
        if !response.ok { die(response.error ?? "read failed") }
        if args.json {
            printJSON(response.withResolvedAppLinks())
        } else if let content = response.content {
            print(content)
        }

    case "note", "add-note", "append-note":
        guard let id = args.positionals.first else { die("note requires an id") }
        var text = expandEscapes(args.positionals.dropFirst().joined(separator: " "))
        if text.isEmpty, let piped = readStdin() { text = piped }
        if text.isEmpty, let note = args.note { text = note }
        if text.isEmpty { die("note requires text") }

        let response = await send(BookmarkedRequest(type: "note", id: id, idPrefix: id, note: text))
        if !response.ok { die(response.error ?? "note failed") }
        if args.json {
            printJSON(response.withResolvedAppLinks())
        } else if !args.quiet, let item = response.item {
            print("noted: \(item.title)")
        }

    case "tag":
        guard args.positionals.count >= 3 else {
            die("tag requires: bookmarked tag <id> add|rm|set <tag>")
        }
        let id = args.positionals[0]
        let action = args.positionals[1]
        let tag = args.positionals.dropFirst(2).joined(separator: " ")
        let response = await send(BookmarkedRequest(type: "tag", id: id, idPrefix: id, tag: tag, tagAction: action))
        if !response.ok { die(response.error ?? "tag failed") }
        if args.json {
            printJSON(response.withResolvedAppLinks())
        } else if !args.quiet, let item = response.item {
            print("tags: \(item.tags.joined(separator: ", "))")
        }

    default:
        FileHandle.standardError.write("bookmarked: unknown command \(args.command)\n\n".data(using: .utf8)!)
        FileHandle.standardError.write(USAGE.data(using: .utf8)!)
        exit(1)
    }
}

let semaphore = DispatchSemaphore(value: 0)
Task {
    await run()
    semaphore.signal()
}
semaphore.wait()
