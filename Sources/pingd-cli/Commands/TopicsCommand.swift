import ArgumentParser
import Foundation

struct TopicsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "topics",
        abstract: "Manage topics",
        subcommands: [List.self, Stats.self, Create.self, Update.self, Delete.self]
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
                    let access = "read=\(topic.publicRead ? "public" : "private") publish=\(topic.publicPublish ? "public" : "private")"
                    print("\(topic.name)  \(access)")
                }
            }
        }
    }

    struct Create: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Create a topic")

        @Option(name: .shortAndLong, help: "Topic name")
        var name: String

        @Flag(name: .long, help: "Allow anyone to read this topic")
        var publicRead: Bool = false

        @Flag(name: .long, help: "Allow anyone to publish to this topic")
        var publicPublish: Bool = false

        func run() async throws {
            try await withAPIClient { client in
                let body = CreateTopicBody(
                    name: name,
                    publicRead: publicRead,
                    publicPublish: publicPublish
                )
                let topic = try await client.post("/topics", body: body, as: TopicDTO.self)
                let access = "read=\(topic.publicRead ? "public" : "private") publish=\(topic.publicPublish ? "public" : "private")"
                print("Created topic '\(topic.name)' (\(access))")
            }
        }

        struct CreateTopicBody: Encodable {
            let name: String
            let publicRead: Bool
            let publicPublish: Bool
        }
    }

    struct Update: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Update topic access flags")

        @Option(name: .shortAndLong, help: "Topic name")
        var name: String

        @Flag(inversion: .prefixedNo, help: "Allow anyone to read this topic")
        var publicRead: Bool?

        @Flag(inversion: .prefixedNo, help: "Allow anyone to publish to this topic")
        var publicPublish: Bool?

        func run() async throws {
            if publicRead == nil && publicPublish == nil {
                throw ValidationError("Pass at least one of --[no-]public-read or --[no-]public-publish")
            }
            try await withAPIClient { client in
                let body = UpdateTopicBody(publicRead: publicRead, publicPublish: publicPublish)
                let topic = try await client.patch("/topics/\(name)", body: body, as: TopicDTO.self)
                let access = "read=\(topic.publicRead ? "public" : "private") publish=\(topic.publicPublish ? "public" : "private")"
                print("Updated topic '\(topic.name)' (\(access))")
            }
        }

        struct UpdateTopicBody: Encodable {
            let publicRead: Bool?
            let publicPublish: Bool?
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
                let deliveries = stats.deliveryStats
                print("Deliveries: pending=\(deliveries.pending) ongoing=\(deliveries.ongoing) " +
                    "delivered=\(deliveries.delivered) failed=\(deliveries.failed)")
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
