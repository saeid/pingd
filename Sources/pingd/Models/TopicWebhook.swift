import Fluent
import Foundation

struct WebhookTemplate: Codable {
    var title: String?
    var subtitle: String?
    var body: String?
    var tags: String?
    var priority: UInt8?
    var ttl: Int?
}

final class TopicWebhook: Model, @unchecked Sendable {
    static let schema = "topic_webhooks"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "topic_id")
    var topic: Topic

    @Field(key: "token_hash")
    var tokenHash: String

    @Field(key: "template")
    var template: WebhookTemplate

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        topicID: UUID,
        tokenHash: String,
        template: WebhookTemplate
    ) {
        self.id = id
        $topic.id = topicID
        self.tokenHash = tokenHash
        self.template = template
    }
}
