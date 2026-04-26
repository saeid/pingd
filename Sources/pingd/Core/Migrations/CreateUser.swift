import Fluent

struct CreateUser: AsyncMigration {
    func prepare(on database: any Database) async throws {
        let userRole = try await database.enum("user_role")
            .case("user")
            .case("admin")
            .case("guest")
            .create()

        try await database.schema("users")
            .id()
            .field("username", .string, .required)
            .field("password_hash", .string, .required)
            .field("role", userRole, .required)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .field("deleted_at", .datetime)
            .unique(on: "username")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema("users").delete()
        try await database.enum("user_role").delete()
    }
}
