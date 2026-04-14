import Fluent
import Foundation

struct MessagePayload: Codable {
    let title: String?
    let subtitle: String?
    let body: String
}

final class Message: Model, @unchecked Sendable {
    static let schema = "messages"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "topic_id")
    var topic: Topic

    @Field(key: "time")
    var time: Date

    @Field(key: "priority")
    var priority: UInt8

    @OptionalField(key: "tags")
    var tags: [String]?

    @Field(key: "payload")
    var payload: MessagePayload

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        topicID: UUID,
        time: Date,
        priority: UInt8 = 3,
        tags: [String]? = nil,
        payload: MessagePayload
    ) {
        self.id = id
        $topic.id = topicID
        self.time = time
        self.priority = priority
        self.tags = tags
        self.payload = payload
    }
}
