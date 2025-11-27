import Fluent

struct CreateDevice: AsyncMigration {
    func prepare(on database: any Database) async throws {
        let platformEnum = try await database.enum("device_platform")
            .case("ios")
            .case("android")
            .case("web")
            .create()

        let pushTypeEnum = try await database.enum("device_push_type")
            .case("apns")
            .case("fcm")
            .case("webpush")
            .create()

        try await database.schema("devices")
            .id()
            .field("user_id", .uuid, .references("users", "id", onDelete: .cascade))
            .field("platform", platformEnum, .required)
            .field("push_type", pushTypeEnum, .required)
            .field("push_token", .string, .required)
            .field("isActive", .bool, .required, .sql(.default(true)))
            .field("created_at", .datetime)
            .field("last_activity_at", .datetime)
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema("devices").delete()
        try await database.enum("device_platform").delete()
        try await database.enum("device_push_type").delete()
    }
}
