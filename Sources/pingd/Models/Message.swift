import Fluent
import Vapor

final class Message: Model, @unchecked Sendable {
    static let schema = "messages"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "topic_id")
    var topic: Topic

    @Field(key: "time")
    var time: Date

    @OptionalField(key: "title")
    var title: String?

    @OptionalField(key: "subtitle")
    var subtitle: String?

    @Field(key: "body")
    var body: String

    @Field(key: "priority")
    var priority: UInt8

    @OptionalField(key: "tags")
    var tags: [String]?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        topicID: UUID,
        time: Date,
        title: String?,
        subtitle: String?,
        body: String,
        priority: UInt8,
        tags: [String]?
    ) {
        self.id = id
        $topic.id = topicID
        self.time = time
        self.title = title
        self.subtitle = subtitle
        self.priority = priority
        self.body = body
        self.tags = tags
    }
}
