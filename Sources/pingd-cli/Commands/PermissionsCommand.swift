import ArgumentParser
import Foundation

struct PermissionsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "permissions",
        abstract: "Manage permissions",
        subcommands: [List.self, ListGlobal.self, Create.self, CreateGlobal.self, Delete.self]
    )

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List permissions for a user")

        @Option(name: .shortAndLong, help: "Username")
        var username: String

        func run() async throws {
            try await withAPIClient { client in
                let permissions = try await client.get("/permissions/\(username)", as: [PermissionDTO].self)
                if permissions.isEmpty {
                    print("No permissions for '\(username)'")
                    return
                }
                for permission in permissions {
                    print("\(permission.topicPattern)  \(permission.accessLevel)  \(permission.scope)  \(formatExpiry(permission.expiresAt))  \(permission.id)")
                }
            }
        }
    }

    struct ListGlobal: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list-global",
            abstract: "List global permissions"
        )

        func run() async throws {
            try await withAPIClient { client in
                let permissions = try await client.get("/permissions", as: [PermissionDTO].self)
                if permissions.isEmpty {
                    print("No global permissions")
                    return
                }
                for permission in permissions {
                    print("\(permission.topicPattern)  \(permission.accessLevel)  \(formatExpiry(permission.expiresAt))  \(permission.id)")
                }
            }
        }
    }

    struct Create: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Create a user permission")

        @Option(name: .shortAndLong, help: "Username")
        var username: String

        @Option(name: .shortAndLong, help: "Access level: ro, wo, rw, deny")
        var access: String

        @Option(name: .shortAndLong, help: "Topic pattern (e.g. alerts.*, alerts.>, *)")
        var pattern: String

        @Option(name: .long, help: "Expires in duration (e.g. 30d, 12h, 5m)")
        var expiresIn: String?

        func run() async throws {
            let expiry = try parseExpiresIn(expiresIn)
            try await withAPIClient { client in
                let body = CreatePermissionDTO(accessLevel: access, topicPattern: pattern, expiresAt: expiry)
                let permission = try await client.post("/permissions/\(username)", body: body, as: PermissionDTO.self)
                print("Created permission: \(permission.topicPattern) \(permission.accessLevel) for '\(username)' \(formatExpiry(permission.expiresAt))")
            }
        }
    }

    struct CreateGlobal: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "create-global",
            abstract: "Create a global permission"
        )

        @Option(name: .shortAndLong, help: "Access level: ro, wo, rw, deny")
        var access: String

        @Option(name: .shortAndLong, help: "Topic pattern (e.g. alerts.*, alerts.>, *)")
        var pattern: String

        @Option(name: .long, help: "Expires in duration (e.g. 30d, 12h, 5m)")
        var expiresIn: String?

        func run() async throws {
            let expiry = try parseExpiresIn(expiresIn)
            try await withAPIClient { client in
                let body = CreatePermissionDTO(accessLevel: access, topicPattern: pattern, expiresAt: expiry)
                let permission = try await client.post("/permissions", body: body, as: PermissionDTO.self)
                print("Created global permission: \(permission.topicPattern) \(permission.accessLevel) \(formatExpiry(permission.expiresAt))")
            }
        }
    }

    struct Delete: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Delete a permission")

        @Option(name: .shortAndLong, help: "Permission ID")
        var id: String

        func run() async throws {
            try await withAPIClient { client in
                try await client.delete("/permissions/\(id)")
                print("Deleted permission \(id)")
            }
        }
    }
}
