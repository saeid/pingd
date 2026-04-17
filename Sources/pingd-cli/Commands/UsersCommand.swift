import ArgumentParser
import Foundation

struct UsersCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "users",
        abstract: "Manage users",
        subcommands: [List.self, Get.self, Create.self, Update.self, Delete.self]
    )

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List all users")

        func run() async throws {
            try await withAPIClient { client in
                let users = try await client.get("/users", as: [UserDTO].self)
                if users.isEmpty {
                    print("No users")
                    return
                }
                for user in users {
                    print("\(user.username)  \(user.role)")
                }
            }
        }
    }

    struct Get: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Get a user")

        @Option(name: .shortAndLong, help: "Username")
        var username: String

        func run() async throws {
            try await withAPIClient { client in
                let user = try await client.get("/users/\(username)", as: UserDTO.self)
                print("Username: \(user.username)")
                print("Role: \(user.role)")
                print("ID: \(user.id)")
            }
        }
    }

    struct Create: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Create a user")

        @Option(name: .shortAndLong, help: "Username")
        var username: String

        @Option(name: .shortAndLong, help: "Password")
        var password: String

        @Option(name: .shortAndLong, help: "Role: admin, user")
        var role: String = "user"

        func run() async throws {
            try await withAPIClient { client in
                let body = ["username": username, "password": password, "role": role]
                let user = try await client.post("/users", body: body, as: UserDTO.self)
                print("Created user '\(user.username)' (\(user.role))")
            }
        }
    }

    struct Update: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Update a user")

        @Option(name: .shortAndLong, help: "Username")
        var username: String

        @Option(name: .shortAndLong, help: "New password")
        var password: String?

        @Option(name: .shortAndLong, help: "New role: admin, user")
        var role: String?

        func run() async throws {
            try await withAPIClient { client in
                var body: [String: String] = [:]
                if let password { body["password"] = password }
                if let role { body["role"] = role }
                let user = try await client.patch("/users/\(username)", body: body, as: UserDTO.self)
                print("Updated user '\(user.username)' (\(user.role))")
            }
        }
    }

    struct Delete: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Delete a user")

        @Option(name: .shortAndLong, help: "Username")
        var username: String

        func run() async throws {
            try await withAPIClient { client in
                try await client.delete("/users/\(username)")
                print("Deleted user '\(username)'")
            }
        }
    }
}
