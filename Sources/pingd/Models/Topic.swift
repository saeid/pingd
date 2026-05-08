import Fluent
import Foundation

final class Topic: Model, @unchecked Sendable {
    static let schema = "topics"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "name")
    var name: String

    @Parent(key: "owner_user_id")
    var owner: User

    @Field(key: "public_read")
    var publicRead: Bool

    @Field(key: "public_publish")
    var publicPublish: Bool

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
        publicRead: Bool = false,
        publicPublish: Bool = false
    ) {
        self.id = id
        self.name = name
        self.publicRead = publicRead
        self.publicPublish = publicPublish
        $owner.id = ownerUserID
    }
}
