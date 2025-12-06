import Fluent
import Vapor

enum UserRole: String, Codable, CaseIterable {
    case user
    case admin
}

final class User: Model, @unchecked Sendable {
    static let schema = "users"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "username")
    var username: String

    @Field(key: "password_hash")
    var passwordHash: String

    @Enum(key: "role")
    var role: UserRole

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    @Timestamp(key: "deleted_at", on: .delete)
    var deletedAt: Date?

    @Children(for: \.$user)
    var tokens: [Token]

    @Children(for: \.$owner)
    var ownedTopics: [Topic]

    @Children(for: \.$user)
    var permissions: [Permission]

    init() {}

    init(
        id: UUID? = nil,
        username: String,
        passwordHash: String,
        role: UserRole = .user
    ) {
        self.id = id
        self.username = username
        self.passwordHash = passwordHash
        self.role = role
    }
}
