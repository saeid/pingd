import Fluent

struct CreateMessage: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("messages")
            .id()
            .field("topic_id", .uuid, .required, .references("topics", "id", onDelete: .cascade))
            .field("time", .datetime, .required)
            .field("priority", .int8, .required, .sql(.default(3)))
            .field("tags", .json)
            .field("payload", .json, .required)
            .field("expires_at", .datetime)
            .field("created_at", .datetime)
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema("messages").delete()
    }
}
