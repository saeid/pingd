import Vapor

struct WebhookAdminController: RouteCollection, @unchecked Sendable {
    let webhookFeature: WebhookFeature
    let auditLogger: AuditLogger

    func boot(routes: any RoutesBuilder) throws {
        let topicWebhooks = routes.grouped("topics", ":name", "webhooks")
        topicWebhooks.get(use: list)
        topicWebhooks.post(use: create)

        let webhookByID = routes.grouped("webhooks", ":id")
        webhookByID.get(use: show)
        webhookByID.patch(use: update)
        webhookByID.delete(use: delete)
    }

    func list(_ req: Request) async throws -> [WebhookResponse] {
        let currentUser = try req.user
        guard let topicName = req.parameters.get("name") else { throw Abort(.badRequest) }
        let webhooks = try await webhookFeature.listWebhooks(currentUser, topicName)
        return try webhooks.map(WebhookResponse.init)
    }

    func create(_ req: Request) async throws -> CreateWebhookResponse {
        let currentUser = try req.user
        guard let topicName = req.parameters.get("name") else { throw Abort(.badRequest) }
        let body = try req.content.decode(CreateWebhookRequest.self)
        do {
            let created = try await webhookFeature.createWebhook(currentUser, topicName, body.template)
            auditLogger.log("webhook.create", req: req, metadata: [
                "actor_username": currentUser.username,
                "topic_name": topicName,
                "webhook_id": (try? created.webhook.requireID().uuidString) ?? "",
                "ip": req.clientIP,
            ])
            return try CreateWebhookResponse(webhook: created.webhook, token: created.plaintextToken)
        } catch {
            auditLogger.logError("webhook.create", req: req, error: error, metadata: [
                "actor_username": currentUser.username,
                "topic_name": topicName,
                "ip": req.clientIP,
            ])
            throw error
        }
    }

    func show(_ req: Request) async throws -> WebhookResponse {
        let currentUser = try req.user
        guard let idString = req.parameters.get("id"), let id = UUID(uuidString: idString) else {
            throw Abort(.badRequest)
        }
        let webhook = try await webhookFeature.getWebhook(currentUser, id)
        return try WebhookResponse(webhook)
    }

    func update(_ req: Request) async throws -> WebhookResponse {
        let currentUser = try req.user
        guard let idString = req.parameters.get("id"), let id = UUID(uuidString: idString) else {
            throw Abort(.badRequest)
        }
        let body = try req.content.decode(UpdateWebhookRequest.self)
        do {
            let updated = try await webhookFeature.updateWebhook(currentUser, id, body.template)
            auditLogger.log("webhook.update", req: req, metadata: [
                "actor_username": currentUser.username,
                "webhook_id": idString,
                "ip": req.clientIP,
            ])
            return try WebhookResponse(updated)
        } catch {
            auditLogger.logError("webhook.update", req: req, error: error, metadata: [
                "actor_username": currentUser.username,
                "webhook_id": idString,
                "ip": req.clientIP,
            ])
            throw error
        }
    }

    func delete(_ req: Request) async throws -> HTTPStatus {
        let currentUser = try req.user
        guard let idString = req.parameters.get("id"), let id = UUID(uuidString: idString) else {
            throw Abort(.badRequest)
        }
        do {
            try await webhookFeature.deleteWebhook(currentUser, id)
            auditLogger.log("webhook.delete", req: req, metadata: [
                "actor_username": currentUser.username,
                "webhook_id": idString,
                "ip": req.clientIP,
            ])
            return .noContent
        } catch {
            auditLogger.logError("webhook.delete", req: req, error: error, metadata: [
                "actor_username": currentUser.username,
                "webhook_id": idString,
                "ip": req.clientIP,
            ])
            throw error
        }
    }

}

struct WebhookReceiveController: RouteCollection, @unchecked Sendable {
    let webhookFeature: WebhookFeature
    let now: @Sendable () -> Date
    let auditLogger: AuditLogger

    func boot(routes: any RoutesBuilder) throws {
        let hooks = routes.grouped("hooks")
        hooks.on(.POST, ":token", body: .collect(maxSize: "256kb"), use: receive)
    }

    func receive(_ req: Request) async throws -> HTTPStatus {
        guard let token = req.parameters.get("token") else { throw Abort(.notFound) }
        guard var buffer = req.body.data, buffer.readableBytes > 0 else {
            throw Abort(.badRequest, reason: "empty body")
        }
        guard let rawBody = buffer.readString(length: buffer.readableBytes) else {
            throw Abort(.badRequest, reason: "invalid body encoding")
        }
        let bodyByteCount = rawBody.utf8.count
        do {
            let message = try await webhookFeature.receivePayload(token, rawBody, now())
            auditLogger.log("webhook.receive", req: req, metadata: [
                "topic_id": message.$topic.id.uuidString,
                "message_id": (try? message.requireID().uuidString) ?? "",
                "bytes": "\(bodyByteCount)",
                "ip": req.clientIP,
            ])
            return .accepted
        } catch {
            auditLogger.logError("webhook.receive", req: req, error: error, metadata: [
                "bytes": "\(bodyByteCount)",
                "ip": req.clientIP,
            ])
            throw error
        }
    }
}

// MARK: - DTOs

struct WebhookResponse: Content {
    let id: UUID
    let topicID: UUID
    let template: WebhookTemplate
    let createdAt: Date?

    init(_ webhook: TopicWebhook) throws {
        self.id = try webhook.requireID()
        self.topicID = webhook.$topic.id
        self.template = webhook.template
        self.createdAt = webhook.createdAt
    }
}

struct CreateWebhookResponse: Content {
    let id: UUID
    let topicID: UUID
    let token: String
    let template: WebhookTemplate
    let createdAt: Date?

    init(webhook: TopicWebhook, token: String) throws {
        self.id = try webhook.requireID()
        self.topicID = webhook.$topic.id
        self.token = token
        self.template = webhook.template
        self.createdAt = webhook.createdAt
    }
}

struct CreateWebhookRequest: Content {
    let template: WebhookTemplate
}

struct UpdateWebhookRequest: Content {
    let template: WebhookTemplate
}
