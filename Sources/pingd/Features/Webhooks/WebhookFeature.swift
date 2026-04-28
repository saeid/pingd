import Crypto
import Foundation
import Vapor

enum WebhookError: AbortError {
    case topicNotFound
    case webhookNotFound
    case accessDenied
    case invalidPayload(String)

    var status: HTTPResponseStatus {
        switch self {
        case .topicNotFound: .notFound
        case .webhookNotFound: .notFound
        case .accessDenied: .forbidden
        case .invalidPayload: .badRequest
        }
    }

    var reason: String {
        switch self {
        case .topicNotFound: "Topic not found"
        case .webhookNotFound: "Webhook not found"
        case .accessDenied: "Access denied"
        case .invalidPayload(let message): message
        }
    }
}

struct CreatedWebhook {
    let webhook: TopicWebhook
    let plaintextToken: String
}

struct WebhookFeature {
    let createWebhook: @Sendable (
        _ currentUser: User,
        _ topicName: String,
        _ template: WebhookTemplate
    ) async throws -> CreatedWebhook

    let listWebhooks: @Sendable (
        _ currentUser: User,
        _ topicName: String
    ) async throws -> [TopicWebhook]

    let getWebhook: @Sendable (
        _ currentUser: User,
        _ webhookID: UUID
    ) async throws -> TopicWebhook

    let updateWebhook: @Sendable (
        _ currentUser: User,
        _ webhookID: UUID,
        _ template: WebhookTemplate
    ) async throws -> TopicWebhook

    let deleteWebhook: @Sendable (
        _ currentUser: User,
        _ webhookID: UUID
    ) async throws -> Void

    let receivePayload: @Sendable (
        _ token: String,
        _ rawBody: String,
        _ now: Date
    ) async throws -> Message
}

extension WebhookFeature {
    static func tokenHash(_ token: String) -> String {
        let digest = SHA256.hash(data: Data(token.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func validate(template: WebhookTemplate) throws {
        if let priority = template.priority, !(1...3).contains(priority) {
            throw WebhookError.invalidPayload("priority must be between 1 and 3")
        }
        if let ttl = template.ttl {
            guard ttl > 0 else {
                throw WebhookError.invalidPayload("ttl must be positive")
            }
            guard ttl <= 60 * 60 * 24 * 30 else {
                throw WebhookError.invalidPayload("ttl must be <= 30 days")
            }
        }
    }

    static func generateToken(length: Int = 32) -> String {
        let randomPart = [UInt8].random(count: length).base64
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "whk_\(randomPart)"
    }
}

extension WebhookFeature {
    static func live(
        webhookClient: WebhookClient,
        topicClient: TopicClient,
        messageClient: MessageClient,
        dispatchFeature: DispatchFeature,
        topicBroadcaster: TopicBroadcaster
    ) -> Self {
        @Sendable func ensureCanManage(_ topic: Topic, _ user: User) throws {
            if user.role == .admin { return }
            if (try? user.requireID()) == topic.$owner.id { return }
            throw WebhookError.accessDenied
        }

        return WebhookFeature(
            createWebhook: { currentUser, topicName, template in
                try validate(template: template)
                guard let topic = try await topicClient.getByName(topicName) else {
                    throw WebhookError.topicNotFound
                }
                try ensureCanManage(topic, currentUser)
                let token = generateToken()
                let topicID = try topic.requireID()
                let webhook = try await webhookClient.create(topicID, tokenHash(token), template)
                return CreatedWebhook(webhook: webhook, plaintextToken: token)
            },
            listWebhooks: { currentUser, topicName in
                guard let topic = try await topicClient.getByName(topicName) else {
                    throw WebhookError.topicNotFound
                }
                try ensureCanManage(topic, currentUser)
                let topicID = try topic.requireID()
                return try await webhookClient.listByTopic(topicID)
            },
            getWebhook: { currentUser, webhookID in
                guard let webhook = try await webhookClient.get(webhookID) else {
                    throw WebhookError.webhookNotFound
                }
                try ensureCanManage(webhook.topic, currentUser)
                return webhook
            },
            updateWebhook: { currentUser, webhookID, template in
                try validate(template: template)
                guard let webhook = try await webhookClient.get(webhookID) else {
                    throw WebhookError.webhookNotFound
                }
                try ensureCanManage(webhook.topic, currentUser)
                guard let updated = try await webhookClient.updateTemplate(webhookID, template) else {
                    throw WebhookError.webhookNotFound
                }
                return updated
            },
            deleteWebhook: { currentUser, webhookID in
                guard let webhook = try await webhookClient.get(webhookID) else {
                    throw WebhookError.webhookNotFound
                }
                try ensureCanManage(webhook.topic, currentUser)
                try await webhookClient.delete(webhookID)
            },
            receivePayload: { token, rawBody, now in
                guard let webhook = try await webhookClient.findByTokenHash(tokenHash(token)) else {
                    throw WebhookError.webhookNotFound
                }
                let topicID = webhook.$topic.id
                let parsedJSON: Any? = rawBody.data(using: .utf8).flatMap { data in
                    try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
                }

                let template = webhook.template
                let payload = makePayload(template: template, json: parsedJSON, rawBody: rawBody)
                let priority = template.priority ?? 2
                let tags = makeTags(template: template, json: parsedJSON)
                let expiresAt = template.ttl.map { now.addingTimeInterval(TimeInterval($0)) }

                let message = try await messageClient.publish(
                    topicID,
                    priority,
                    tags,
                    payload,
                    now,
                    expiresAt
                )

                let messageID = try message.requireID()
                try await dispatchFeature.fanOut(messageID, topicID)

                let broadcast = BroadcastMessage(
                    priority: priority,
                    tags: tags,
                    payload: payload,
                    time: now
                )
                await topicBroadcaster.broadcast(topic: webhook.topic.name, message: broadcast)

                return message
            }
        )
    }

    private static func makePayload(
        template: WebhookTemplate,
        json: Any?,
        rawBody: String
    ) -> MessagePayload {
        let renderContext: Any = json ?? [:]
        let title = template.title.flatMap {
            let rendered = WebhookTemplateRenderer.render($0, json: renderContext)
            return rendered.isEmpty ? nil : truncate(rendered, limit: 256)
        }
        let subtitle = template.subtitle.flatMap {
            let rendered = WebhookTemplateRenderer.render($0, json: renderContext)
            return rendered.isEmpty ? nil : truncate(rendered, limit: 256)
        }
        let body: String
        if let bodyTemplate = template.body, !bodyTemplate.isEmpty {
            body = truncate(WebhookTemplateRenderer.render(bodyTemplate, json: renderContext))
        } else {
            body = truncate(rawBody)
        }
        return MessagePayload(title: title, subtitle: subtitle, body: body)
    }

    private static func makeTags(template: WebhookTemplate, json: Any?) -> [String]? {
        guard let tagsTemplate = template.tags, !tagsTemplate.isEmpty else { return nil }
        let renderContext: Any = json ?? [:]
        let rendered = WebhookTemplateRenderer.render(tagsTemplate, json: renderContext)
        let tags = MessageTagValidator.filter(WebhookTemplateRenderer.splitTags(rendered))
        return tags.isEmpty ? nil : tags
    }

    private static func truncate(_ value: String, limit: Int = 4_000) -> String {
        if value.count <= limit { return value }
        return String(value.prefix(limit))
    }
}
