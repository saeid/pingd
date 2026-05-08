import Fluent

struct CreateTopicShareToken: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("topic_share_tokens")
            .id()
            .field("topic_id", .uuid, .required, .references("topics", "id", onDelete: .cascade))
            .field("token_hash", .string, .required)
            .field("label", .string)
            .field("access_level", .string, .required)
            .field("created_by_user_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("expires_at", .datetime)
            .field("created_at", .datetime)
            .unique(on: "token_hash")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema("topic_share_tokens").delete()
    }
}
