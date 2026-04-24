import ArgumentParser
import Foundation

struct TokensCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tokens",
        abstract: "Manage tokens",
        subcommands: [List.self, Create.self, Revoke.self]
    )

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List tokens for a user")

        @Option(name: .shortAndLong, help: "Username")
        var username: String

        func run() async throws {
            try await withAPIClient { client in
                let tokens = try await client.get("/users/\(username)/tokens", as: [TokenDTO].self)
                if tokens.isEmpty {
                    print("No tokens")
                    return
                }
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
                for token in tokens {
                    let label = token.label ?? "no label"
                    let expiry = token.expiresAt.map { formatter.string(from: $0) } ?? "never"
                    print("\(token.id)  \(label)  \(expiry)  \(token.token)")
                }
            }
        }
    }

    struct Create: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Create a token for a user")

        @Option(name: .shortAndLong, help: "Username")
        var username: String

        @Option(name: .shortAndLong, help: "Token label")
        var label: String?

        @Option(name: .shortAndLong, help: "Expires in duration (e.g. 30d, 12h, 90d)")
        var expiresIn: String?

        func run() async throws {
            try await withAPIClient { client in
                var body: [String: String] = [:]
                if let label { body["label"] = label }
                if let expiresIn {
                    guard let seconds = parseDuration(expiresIn) else {
                        print("Invalid duration: \(expiresIn). Use format like 30d, 12h, 90d")
                        return
                    }
                    let expiresAt = Date().addingTimeInterval(seconds)
                    body["expiresAt"] = ISO8601DateFormatter().string(from: expiresAt)
                }
                let token = try await client.post("/users/\(username)/tokens", body: body, as: TokenDTO.self)
                print("Created token: \(token.id)  \(token.token)")
            }
        }

        func parseDuration(_ input: String) -> TimeInterval? {
            let pattern = /^(\d+)([dhm])$/
            guard let match = input.wholeMatch(of: pattern),
                  let value = Double(match.1), value > 0 else { return nil }
            switch match.2 {
            case "d": return value * 86400
            case "h": return value * 3600
            case "m": return value * 60
            default: return nil
            }
        }
    }

    struct Revoke: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Revoke a token")

        @Option(name: .shortAndLong, help: "Token ID")
        var id: String

        func run() async throws {
            try await withAPIClient { client in
                try await client.delete("/tokens/\(id)")
                print("Revoked token \(id)")
            }
        }
    }
}
