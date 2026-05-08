import Fluent
import Foundation

final class TopicShareToken: Model, @unchecked Sendable {
    static let schema = "topic_share_tokens"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "topic_id")
    var topic: Topic

    @Field(key: "token_hash")
    var tokenHash: String

    @OptionalField(key: "label")
    var label: String?

    @Enum(key: "access_level")
    var accessLevel: AccessLevel

    @Parent(key: "created_by_user_id")
    var createdBy: User

    @OptionalField(key: "expires_at")
    var expiresAt: Date?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        topicID: UUID,
        tokenHash: String,
        label: String?,
        accessLevel: AccessLevel,
        createdByUserID: UUID,
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.tokenHash = tokenHash
        self.label = label
        self.accessLevel = accessLevel
        self.expiresAt = expiresAt
        $topic.id = topicID
        $createdBy.id = createdByUserID
    }
}
