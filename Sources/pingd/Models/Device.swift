import Fluent
import Foundation

enum Platform: String, Codable, CaseIterable {
    case ios
    case android
    case web
}

enum PushType: String, Codable, CaseIterable {
    case apns
    case fcm
    case webPush = "webpush"
}

final class Device: Model, @unchecked Sendable {
    static let schema = "devices"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "user_id")
    var user: User

    @Enum(key: "platform")
    var platform: Platform

    @Enum(key: "push_type")
    var pushType: PushType

    @Field(key: "name")
    var name: String

    @Field(key: "push_token")
    var pushToken: String

    @Field(key: "is_active")
    var isActive: Bool

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @OptionalField(key: "last_activity_at")
    var lastActivityAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        userID: UUID,
        name: String,
        platform: Platform,
        pushType: PushType,
        pushToken: String,
        isActive: Bool = true,
        lastActivityAt: Date? = nil
    ) {
        self.id = id
        $user.id = userID
        self.name = name
        self.platform = platform
        self.pushType = pushType
        self.pushToken = pushToken
        self.isActive = isActive
        self.lastActivityAt = lastActivityAt
    }
}
