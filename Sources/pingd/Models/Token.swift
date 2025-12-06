import Fluent
import Vapor

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

    @OptionalField(key: "revoked_at")
    var revokedAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        userID: UUID,
        tokenHash: String
    ) {
        self.id = id
        $user.id = userID
        self.tokenHash = tokenHash
    }

    var isRevoked: Bool {
        revokedAt != nil
    }
}
