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
            try await withAPIClient { client in
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
            try await withAPIClient { client in
                let request = PublishRequest(
                    priority: priority,
                    tags: nil,
                    payload: PayloadDTO(title: title, subtitle: nil, body: body)
                )
                let msg = try await client.post("/topics/\(topic)/messages", body: request, as: MessageDTO.self)
                print("Published to '\(topic)': \(msg.payload.body)")
            }
        }
    }

    struct Watch: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Watch messages on a topic via SSE")

        @Option(name: .shortAndLong, help: "Topic name")
        var topic: String

        func run() async throws {
            print("Watching '\(topic)' (Ctrl+C to stop)")
            try await withAPIClient { client in
                var delay: UInt64 = 2
                while !Task.isCancelled {
                    do {
                        let response = try await client.openStream("/topics/\(topic)/stream")
                        print("Connected.")
                        delay = 2

                        try await client.consumeStream(response) { data in
                            guard let payload = try? JSONDecoder().decode(PayloadDTO.self, from: data) else {
                                return
                            }
                            let title = payload.title.map { "\($0): " } ?? ""
                            print("\(title)\(payload.body)")
                        }

                        print("Stream ended.")
                    } catch is CancellationError {
                        break
                    } catch {
                        print("Connection lost. Reconnecting in \(delay)s...")
                        try await Task.sleep(for: .seconds(delay))
                        delay = min(delay * 2, 30)
                    }
                }
            }
        }
    }
}
