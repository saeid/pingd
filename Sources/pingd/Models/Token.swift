import Fluent
import Foundation

final class Token: Model, @unchecked Sendable {
    static let schema = "tokens"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "user_id")
    var user: User

    @Field(key: "token_hash")
    var tokenHash: String

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @OptionalField(key: "last_used_at")
    var lastUsedAt: Date?

    @OptionalField(key: "last_used_ip")
    var lastUsedIp: String?

    @OptionalField(key: "label")
    var label: String?

    @OptionalField(key: "expires_at")
    var expiresAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        userID: UUID,
        tokenHash: String,
        label: String?,
        expiresAt: Date?
    ) {
        self.id = id
        $user.id = userID
        self.tokenHash = tokenHash
        self.label = label
        self.expiresAt = expiresAt
    }
}
