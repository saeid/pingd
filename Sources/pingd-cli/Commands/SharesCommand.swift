import ArgumentParser
import Foundation

struct SharesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "shares",
        abstract: "Manage topic share tokens",
        subcommands: [List.self, Create.self, Update.self, Rotate.self, Delete.self]
    )

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List share tokens for a topic")

        @Option(name: .shortAndLong, help: "Topic name")
        var topic: String

        func run() async throws {
            try await withAPIClient { client in
                let shares = try await client.get("/topics/\(topic)/shares", as: [TopicShareTokenDTO].self)
                if shares.isEmpty {
                    print("No share tokens for '\(topic)'")
                    return
                }
                for share in shares {
                    let label = share.label ?? "(no label)"
                    print("\(share.id)  \(share.accessLevel)  \(label)  \(formatExpiry(share.expiresAt))")
                }
            }
        }
    }

    struct Create: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Create a share token")

        @Option(name: .shortAndLong, help: "Topic name")
        var topic: String

        @Option(name: .shortAndLong, help: "Access level: ro, wo, rw")
        var access: String

        @Option(name: .shortAndLong, help: "Optional label")
        var label: String?

        @Option(name: .long, help: "Expires in duration (e.g. 30d, 12h, 5m)")
        var expiresIn: String?

        func run() async throws {
            let expiry = try parseExpiresIn(expiresIn)
            try await withAPIClient { client in
                let body = CreateTopicShareDTO(label: label, accessLevel: access, expiresAt: expiry)
                let share = try await client.post("/topics/\(topic)/shares", body: body, as: TopicShareTokenDTO.self)
                print("Created share \(share.id) (\(share.accessLevel))")
                if let raw = share.token {
                    print("Token: \(raw)")
                    print("Copy your token now. It won't be shown again.")
                }
            }
        }
    }

    struct Update: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Update label, access level, or expiry")

        @Option(name: .shortAndLong, help: "Topic name")
        var topic: String

        @Option(name: .shortAndLong, help: "Share ID")
        var id: String

        @Option(name: .shortAndLong, help: "New label")
        var label: String?

        @Option(name: .shortAndLong, help: "New access level: ro, wo, rw")
        var access: String?

        @Option(name: .long, help: "New expiry as duration (e.g. 30d, 12h, 5m)")
        var expiresIn: String?

        func run() async throws {
            if label == nil, access == nil, expiresIn == nil {
                throw ValidationError("Pass at least one of --label, --access, --expires-in")
            }
            let expiry = try parseExpiresIn(expiresIn)
            try await withAPIClient { client in
                let body = UpdateTopicShareDTO(label: label, accessLevel: access, expiresAt: expiry)
                let share = try await client.patch("/topics/\(topic)/shares/\(id)", body: body, as: TopicShareTokenDTO.self)
                print("Updated share \(share.id) (\(share.accessLevel)) \(formatExpiry(share.expiresAt))")
            }
        }
    }

    struct Rotate: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Rotate a share token")

        @Option(name: .shortAndLong, help: "Topic name")
        var topic: String

        @Option(name: .shortAndLong, help: "Share ID")
        var id: String

        func run() async throws {
            try await withAPIClient { client in
                let share = try await client.post("/topics/\(topic)/shares/\(id)/rotate", as: TopicShareTokenDTO.self)
                print("Rotated share \(share.id)")
                if let raw = share.token {
                    print("Token: \(raw)")
                    print("Copy your token now. It won't be shown again.")
                }
            }
        }
    }

    struct Delete: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Delete a share token")

        @Option(name: .shortAndLong, help: "Topic name")
        var topic: String

        @Option(name: .shortAndLong, help: "Share ID")
        var id: String

        func run() async throws {
            try await withAPIClient { client in
                try await client.delete("/topics/\(topic)/shares/\(id)")
                print("Deleted share \(id)")
            }
        }
    }
}
