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
            let client = APIClient(config: ConfigManager.load())
            let tokens = try await client.get("/users/\(username)/tokens", as: [TokenDTO].self)
            if tokens.isEmpty {
                print("No tokens")
                return
            }
            for token in tokens {
                let label = token.label ?? "no label"
                print("\(token.id)  \(label)")
            }
        }
    }

    struct Create: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Create a token for a user")

        @Option(name: .shortAndLong, help: "Username")
        var username: String

        @Option(name: .shortAndLong, help: "Token label")
        var label: String?

        func run() async throws {
            let client = APIClient(config: ConfigManager.load())
            var body: [String: String] = [:]
            if let label { body["label"] = label }
            let token = try await client.post("/users/\(username)/tokens", body: body, as: TokenDTO.self)
            print("Created token: \(token.id)")
        }
    }

    struct Revoke: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Revoke a token")

        @Option(name: .shortAndLong, help: "Token ID")
        var id: String

        func run() async throws {
            let client = APIClient(config: ConfigManager.load())
            try await client.delete("/tokens/\(id)")
            print("Revoked token \(id)")
        }
    }
}
