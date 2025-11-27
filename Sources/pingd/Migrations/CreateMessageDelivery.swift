import Fluent

struct CreateMessageDelivery: AsyncMigration {
    func prepare(on database: any Database) async throws {
        let deliveryStatusEnum = try await database.enum("delivery_status")
            .case("pending")
            .case("ongoing")
            .case("delivered")
            .case("failed")
            .create()

        try await database.schema("messages_delivery")
            .id()
            .field("message_id", .uuid, .required, .references("messages", "id", onDelete: .cascade))
            .field("device_id", .uuid, .required, .references("devices", "id", onDelete: .cascade))
            .field("status", deliveryStatusEnum, .required)
            .field("retry_count", .uint8, .required, .sql(.default(3)))
            .field("created_at", .datetime)
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema("messages_delivery").delete()
        try await database.enum("delivery_status").delete()
    }
}
