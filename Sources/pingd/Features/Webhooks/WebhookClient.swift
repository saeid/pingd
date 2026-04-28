import Fluent
import Foundation
import Vapor

struct WebhookClient {
    let create: @Sendable (
        _ topicID: UUID,
        _ tokenHash: String,
        _ template: WebhookTemplate
    ) async throws -> TopicWebhook
    let get: @Sendable (UUID) async throws -> TopicWebhook?
    let findByTokenHash: @Sendable (String) async throws -> TopicWebhook?
    let listByTopic: @Sendable (UUID) async throws -> [TopicWebhook]
    let updateTemplate: @Sendable (UUID, WebhookTemplate) async throws -> TopicWebhook?
    let delete: @Sendable (UUID) async throws -> Void
}

extension WebhookClient {
    static func live(app: Application) -> Self {
        WebhookClient(
            create: { topicID, tokenHash, template in
                let webhook = TopicWebhook(
                    topicID: topicID,
                    tokenHash: tokenHash,
                    template: template
                )
                try await webhook.save(on: app.db)
                return webhook
            },
            get: { id in
                try await TopicWebhook.query(on: app.db)
                    .filter(\.$id == id)
                    .with(\.$topic)
                    .first()
            },
            findByTokenHash: { hash in
                try await TopicWebhook.query(on: app.db)
                    .filter(\.$tokenHash == hash)
                    .with(\.$topic)
                    .first()
            },
            listByTopic: { topicID in
                try await TopicWebhook.query(on: app.db)
                    .filter(\.$topic.$id == topicID)
                    .sort(\.$createdAt, .descending)
                    .all()
            },
            updateTemplate: { id, template in
                guard let webhook = try await TopicWebhook.find(id, on: app.db) else {
                    return nil
                }
                webhook.template = template
                try await webhook.save(on: app.db)
                return webhook
            },
            delete: { id in
                guard let webhook = try await TopicWebhook.find(id, on: app.db) else { return }
                try await webhook.delete(on: app.db)
            }
        )
    }

    static func mock(
        create: @escaping @Sendable (UUID, String, WebhookTemplate) async throws -> TopicWebhook = { topicID, hash, template in
            TopicWebhook(topicID: topicID, tokenHash: hash, template: template)
        },
        get: @escaping @Sendable (UUID) async throws -> TopicWebhook? = { _ in nil },
        findByTokenHash: @escaping @Sendable (String) async throws -> TopicWebhook? = { _ in nil },
        listByTopic: @escaping @Sendable (UUID) async throws -> [TopicWebhook] = { _ in [] },
        updateTemplate: @escaping @Sendable (UUID, WebhookTemplate) async throws -> TopicWebhook? = { _, _ in nil },
        delete: @escaping @Sendable (UUID) async throws -> Void = { _ in }
    ) -> Self {
        WebhookClient(
            create: create,
            get: get,
            findByTokenHash: findByTokenHash,
            listByTopic: listByTopic,
            updateTemplate: updateTemplate,
            delete: delete
        )
    }
}
