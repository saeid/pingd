import Fluent
import Vapor

final class Topic: Model, @unchecked Sendable {
    static let schema = "topics"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "name")
    var name: String

    @Parent(key: "owner_user_id")
    var owner: User

    @OptionalField(key: "password_hash")
    var passwordHash: String?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    @Children(for: \.$topic)
    var messages: [Message]

    init() {}

    init(
        id: UUID? = nil,
        name: String,
        ownerUserID: UUID,
        passwordHash: String?
    ) {
        self.id = id
        self.name = name
        self.passwordHash = passwordHash
        $owner.id = ownerUserID
    }
}
