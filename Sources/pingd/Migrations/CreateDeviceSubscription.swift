import Fluent

struct CreateDeviceSubscription: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("device_subscriptions")
            .id()
            .field("device_id", .uuid, .required, .references("devices", "id", onDelete: .cascade))
            .field("topic_id", .uuid, .required, .references("topics", "id", onDelete: .cascade))
            .field("created_at", .datetime)
            .unique(on: "device_id", "topic_id")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema("device_subscriptions").delete()
    }
}
