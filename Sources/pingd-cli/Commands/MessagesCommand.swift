import ArgumentParser
import Foundation

struct MessagesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "messages",
        abstract: "Publish and read messages",
        subcommands: [List.self, Publish.self, Watch.self]
    )

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List messages for a topic")

        @Option(name: .shortAndLong, help: "Topic name")
        var topic: String

        @Option(name: .shortAndLong, help: "Number of messages to show")
        var limit: Int = 10

        @Flag(name: .shortAndLong, help: "Show all messages")
        var all: Bool = false

        func run() async throws {
            let client = APIClient(config: ConfigManager.load())
            var messages = try await client.get("/topics/\(topic)/messages", as: [MessageDTO].self)
            if messages.isEmpty {
                print("No messages")
                return
            }
            if !all {
                messages = Array(messages.prefix(limit))
            }
            for msg in messages {
                let title = msg.payload.title.map { "\($0): " } ?? ""
                let tags = msg.tags?.joined(separator: ", ") ?? ""
                print("[\(msg.priority)] \(title)\(msg.payload.body)\(tags.isEmpty ? "" : " [\(tags)]")")
            }
        }
    }

    struct Publish: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Publish a message to a topic")

        @Option(name: .shortAndLong, help: "Topic name")
        var topic: String

        @Option(name: .shortAndLong, help: "Message body")
        var body: String

        @Option(name: .long, help: "Message title")
        var title: String?

        @Option(name: .shortAndLong, help: "Priority 1-5")
        var priority: UInt8 = 3

        func run() async throws {
            let client = APIClient(config: ConfigManager.load())
            let request = PublishRequest(
                priority: priority,
                tags: nil,
                payload: PayloadDTO(title: title, subtitle: nil, body: body)
            )
            let msg = try await client.post("/topics/\(topic)/messages", body: request, as: MessageDTO.self)
            print("Published to '\(topic)': \(msg.payload.body)")
        }
    }

    struct Watch: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Watch messages on a topic via SSE")

        @Option(name: .shortAndLong, help: "Topic name")
        var topic: String

        func run() async throws {
            let client = APIClient(config: ConfigManager.load())
            let bytes = try await client.stream("/topics/\(topic)/stream")

            print("Watching '\(topic)' (Ctrl+C to stop)")

            for try await line in bytes.lines {
                guard line.hasPrefix("data: ") else { continue }
                let json = String(line.dropFirst(6))
                guard let data = json.data(using: .utf8) else { continue }
                if let payload = try? JSONDecoder().decode(PayloadDTO.self, from: data) {
                    let title = payload.title.map { "\($0): " } ?? ""
                    print("\(title)\(payload.body)")
                }
            }
        }
    }
}
