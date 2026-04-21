import Vapor

struct SubscriptionController: RouteCollection, @unchecked Sendable {
    let subscriptionFeature: SubscriptionFeature
    let auditLogger: AuditLogger

    func boot(routes: any RoutesBuilder) throws {
        let subs = routes.grouped("devices", ":id", "subscriptions")
        subs.get(use: list)
        subs.post(use: subscribe)
        subs.delete(":topicName", use: unsubscribe)
    }

    func list(_ req: Request) async throws -> [SubscriptionResponse] {
        guard let id = req.parameters.get("id", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        let subs = try await subscriptionFeature.listSubscriptions(try req.user, id)
        return try subs.map(SubscriptionResponse.init)
    }

    func subscribe(_ req: Request) async throws -> SubscriptionResponse {
        let currentUser = try req.user
        guard let id = req.parameters.get("id", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        let body = try req.content.decode(SubscribeRequest.self)
        do {
            let sub = try await subscriptionFeature.subscribe(currentUser, id, body.topicName)
            auditLogger.log("subscription.create", req: req, metadata: [
                "actor_username": currentUser.username,
                "device_id": id.uuidString,
                "topic_name": body.topicName,
                "ip": req.clientIP,
            ])
            return try SubscriptionResponse(sub)
        } catch {
            auditLogger.logError("subscription.create", req: req, error: error, metadata: [
                "actor_username": currentUser.username,
                "device_id": id.uuidString,
                "topic_name": body.topicName,
                "ip": req.clientIP,
            ])
            throw error
        }
    }

    func unsubscribe(_ req: Request) async throws -> HTTPStatus {
        let currentUser = try req.user
        guard let id = req.parameters.get("id", as: UUID.self),
              let topicName = req.parameters.get("topicName")
        else {
            throw Abort(.badRequest)
        }
        do {
            try await subscriptionFeature.unsubscribe(currentUser, id, topicName)
            auditLogger.log("subscription.delete", req: req, metadata: [
                "actor_username": currentUser.username,
                "device_id": id.uuidString,
                "topic_name": topicName,
                "ip": req.clientIP,
            ])
            return .noContent
        } catch {
            auditLogger.logError("subscription.delete", req: req, error: error, metadata: [
                "actor_username": currentUser.username,
                "device_id": id.uuidString,
                "topic_name": topicName,
                "ip": req.clientIP,
            ])
            throw error
        }
    }
}

// MARK: - DTOs

struct SubscriptionResponse: Content {
    let id: UUID
    let deviceID: UUID
    let topicID: UUID
    let createdAt: Date?

    init(_ subscription: DeviceSubscription) throws {
        self.id = try subscription.requireID()
        self.deviceID = subscription.$device.id
        self.topicID = subscription.$topic.id
        self.createdAt = subscription.createdAt
    }
}

struct SubscribeRequest: Content {
    let topicName: String
}
