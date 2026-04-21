import ArgumentParser
import Foundation

struct TopicsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "topics",
        abstract: "Manage topics",
        subcommands: [List.self, Stats.self, Create.self, Delete.self]
    )

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List all topics")

        func run() async throws {
            try await withAPIClient { client in
                let topics = try await client.get("/topics", as: [TopicDTO].self)
                if topics.isEmpty {
                    print("No topics")
                    return
                }
                for topic in topics {
                    print("\(topic.name)  \(topic.visibility)")
                }
            }
        }
    }

    struct Create: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Create a topic")

        @Option(name: .shortAndLong, help: "Topic name")
        var name: String

        @Option(name: .shortAndLong, help: "Visibility: open, protected, private")
        var visibility: String = "protected"

        func run() async throws {
            try await withAPIClient { client in
                let body = ["name": name, "visibility": visibility]
                let topic = try await client.post("/topics", body: body, as: TopicDTO.self)
                print("Created topic '\(topic.name)' (\(topic.visibility))")
            }
        }
    }

    struct Stats: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Get admin stats for a topic")

        @Option(name: .shortAndLong, help: "Topic name")
        var name: String

        func run() async throws {
            try await withAPIClient { client in
                let stats = try await client.get("/topics/\(name)/stats", as: TopicStatsDTO.self)
                let formatter = ISO8601DateFormatter()

                print("Topic: \(name)")
                print("Subscribers: \(stats.subscriberCount)")
                print("Messages: \(stats.messageCount)")
                print("Last message at: \(stats.lastMessageAt.map(formatter.string(from:)) ?? "none")")
                print(
                    "Deliveries: pending=\(stats.deliveryStats.pending) ongoing=\(stats.deliveryStats.ongoing) delivered=\(stats.deliveryStats.delivered) failed=\(stats.deliveryStats.failed)"
                )
            }
        }
    }

    struct Delete: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Delete a topic")

        @Option(name: .shortAndLong, help: "Topic name")
        var name: String

        func run() async throws {
            try await withAPIClient { client in
                try await client.delete("/topics/\(name)")
                print("Deleted topic '\(name)'")
            }
        }
    }
}
