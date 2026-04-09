import Fluent
import Foundation

enum AccessLevel: String, Codable, CaseIterable {
    case deny
    case readOnly = "ro"
    case writeOnly = "wo"
    case readWrite = "rw"
}

enum PermissionScope: String, Codable, CaseIterable {
    case user
    case `public`
}

final class Permission: Model, @unchecked Sendable {
    static let schema = "permissions"

    @ID(key: .id)
    var id: UUID?

    @OptionalParent(key: "user_id")
    var user: User?

    @Enum(key: "access_level")
    var accessLevel: AccessLevel

    @Enum(key: "scope")
    var scope: PermissionScope

    @Field(key: "topic_pattern")
    var topicPattern: String

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        scope: PermissionScope,
        accessLevel: AccessLevel,
        userId: UUID?,
        topicPattern: String
    ) {
        self.id = id
        self.scope = scope
        self.accessLevel = accessLevel
        self.topicPattern = topicPattern
        $user.id = userId
    }

}
