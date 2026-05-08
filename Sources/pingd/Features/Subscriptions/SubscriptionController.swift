import Vapor

struct SubscriptionController: RouteCollection, @unchecked Sendable {
    let subscriptionFeature: SubscriptionFeature
    let auditLogger: AuditLogger

    func boot(routes: any RoutesBuilder) throws {
        let subs = routes.grouped("devices", ":id", "subscriptions")
        subs.get(use: list)
        subs.post(use: subscribe)
        subs.delete(":topicName", use: unsubscribe)

        let userSubs = routes.grouped("users", ":username", "subscriptions")
        userSubs.get(use: listForUser)
    }

    func list(_ req: Request) async throws -> [SubscriptionResponse] {
        guard let id = req.parameters.get("id", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        let subs = try await subscriptionFeature.listSubscriptions(try req.user, id)
        return try subs.map { try SubscriptionResponse($0, topic: $0.$topic.wrappedValue) }
    }

    func subscribe(_ req: Request) async throws -> SubscriptionResponse {
        let currentUser = try req.user
        guard let id = req.parameters.get("id", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        let body = try req.content.decode(SubscribeRequest.self)
        do {
            let (sub, topic) = try await subscriptionFeature.subscribe(
                currentUser,
                id,
                body.topicName,
                req.topicToken
            )
            auditLogger.log("subscription.create", req: req, metadata: [
                "actor_username": currentUser.username,
                "device_id": id.uuidString,
                "topic_name": body.topicName,
                "ip": req.clientIP,
            ])
            return try SubscriptionResponse(sub, topic: topic)
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
    func listForUser(_ req: Request) async throws -> [UserSubscriptionResponse] {
        guard let username = req.parameters.get("username") else {
            throw Abort(.badRequest)
        }
        return try await subscriptionFeature.listForUser(try req.user, username)
    }
}

// MARK: - DTOs

struct SubscriptionResponse: Content {
    let id: UUID
    let deviceID: UUID
    let topicID: UUID
    let topicName: String
    let topicPublicRead: Bool
    let topicPublicPublish: Bool
    let topicOwnerUserID: UUID
    let createdAt: Date?

    init(_ subscription: DeviceSubscription, topic: Topic) throws {
        self.id = try subscription.requireID()
        self.deviceID = subscription.$device.id
        self.topicID = subscription.$topic.id
        self.topicName = topic.name
        self.topicPublicRead = topic.publicRead
        self.topicPublicPublish = topic.publicPublish
        self.topicOwnerUserID = topic.$owner.id
        self.createdAt = subscription.createdAt
    }
}

struct SubscribeRequest: Content {
    let topicName: String
}

struct UserSubscriptionResponse: Content {
    let id: UUID
    let device: DeviceInfo
    let topic: TopicInfo
    let createdAt: Date?

    struct DeviceInfo: Content {
        let id: UUID
        let name: String
        let platform: String
    }

    struct TopicInfo: Content {
        let id: UUID
        let name: String
        let publicRead: Bool
        let publicPublish: Bool
        let ownerUserID: UUID
    }
}
