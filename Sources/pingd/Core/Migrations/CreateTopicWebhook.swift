import Fluent

struct CreateTopicWebhook: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("topic_webhooks")
            .id()
            .field("topic_id", .uuid, .required, .references("topics", "id", onDelete: .cascade))
            .field("token_hash", .string, .required)
            .field("template", .json, .required)
            .field("created_at", .datetime)
            .unique(on: "token_hash")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema("topic_webhooks").delete()
    }
}
