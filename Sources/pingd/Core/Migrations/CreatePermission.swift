import Fluent

struct CreatePermission: AsyncMigration {
    func prepare(on database: any Database) async throws {
        let scopeEnum = try await database.enum("permission_scope")
            .case("user")
            .case("global")
            .create()

        let accessLevelEnum = try await database.enum("access_level")
            .case("rw")
            .case("ro")
            .case("wo")
            .case("deny")
            .create()

        try await database.schema("permissions")
            .id()
            .field("user_id", .uuid, .references("users", "id", onDelete: .cascade))
            .field("scope", scopeEnum, .required)
            .field("access_level", accessLevelEnum, .required)
            .field("topic_pattern", .string, .required)
            .field("expires_at", .datetime)
            .field("created_at", .datetime)
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema("permissions").delete()
        try await database.enum("permission_scope").delete()
        try await database.enum("access_level").delete()
    }
}
