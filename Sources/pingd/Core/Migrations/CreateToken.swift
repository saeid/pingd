import Fluent

struct CreateToken: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("tokens")
            .id()
            .field("user_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("token_hash", .string, .required)
            .field("created_at", .datetime)
            .field("last_used_at", .datetime)
            .field("last_used_ip", .string)
            .field("label", .string)
            .field("expires_at", .datetime)
            .unique(on: "token_hash")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema("tokens").delete()
    }
}
