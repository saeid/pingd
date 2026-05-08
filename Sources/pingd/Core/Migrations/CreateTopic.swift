import Fluent

struct CreateTopic: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("topics")
            .id()
            .field("name", .string, .required)
            .field("owner_user_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("public_read", .bool, .required, .sql(.default(false)))
            .field("public_publish", .bool, .required, .sql(.default(false)))
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "name")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema("topics").delete()
    }
}
