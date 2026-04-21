import Vapor

struct TopicController: RouteCollection, @unchecked Sendable {
    let topicFeature: TopicFeature
    let authClient: AuthClient
    let auditLogger: AuditLogger

    func boot(routes: any RoutesBuilder) throws {
        let topics = routes.grouped("topics")
        topics.get(use: list)
        topics.post(use: create)
        topics.get(":name", use: get)
        topics.get(":name", "stats", use: stats)
        topics.patch(":name", use: update)
        topics.delete(":name", use: delete)
    }

    func list(_ req: Request) async throws -> [TopicResponse] {
        let topics = try await topicFeature.listTopics(req.optionalUser)
        return try topics.map(TopicResponse.init)
    }

    func create(_ req: Request) async throws -> TopicResponse {
        let currentUser = try req.user
        try CreateTopicRequest.validate(content: req)
        let body = try req.content.decode(CreateTopicRequest.self)
        let passwordHash: String?
        if let password = body.password, !password.isEmpty {
            passwordHash = try authClient.hashPassword(password)
        } else {
            passwordHash = nil
        }
        do {
            let topic = try await topicFeature.createTopic(
                currentUser,
                body.name,
                body.visibility ?? .protected,
                passwordHash
            )
            auditLogger.log("topic.create", req: req, metadata: [
                "actor_username": currentUser.username,
                "actor_role": currentUser.role.rawValue,
                "topic_name": topic.name,
                "visibility": topic.visibility.rawValue,
                "has_password": topic.passwordHash == nil ? "false" : "true",
                "ip": req.clientIP,
            ])
            return try TopicResponse(topic)
        } catch {
            auditLogger.logError("topic.create", req: req, error: error, metadata: [
                "actor_username": currentUser.username,
                "actor_role": currentUser.role.rawValue,
                "topic_name": body.name,
                "visibility": (body.visibility ?? .protected).rawValue,
                "has_password": passwordHash == nil ? "false" : "true",
                "ip": req.clientIP,
            ])
            throw error
        }
    }

    func get(_ req: Request) async throws -> TopicResponse {
        guard let name = req.parameters.get("name") else { throw Abort(.badRequest) }
        let topic = try await topicFeature.getTopic(req.optionalUser, name, req.topicPassword)
        return try TopicResponse(topic)
    }

    func stats(_ req: Request) async throws -> TopicStatsResponse {
        let currentUser = try req.user
        guard let name = req.parameters.get("name") else { throw Abort(.badRequest) }
        let stats = try await topicFeature.topicStats(currentUser, name)
        return TopicStatsResponse(stats)
    }

    func update(_ req: Request) async throws -> TopicResponse {
        let currentUser = try req.user
        guard let name = req.parameters.get("name") else { throw Abort(.badRequest) }
        let body = try req.content.decode(UpdateTopicRequest.self)
        let passwordHash: String?? = try body.password.map { password in
            if password.isEmpty {
                return nil
            }
            return try authClient.hashPassword(password)
        }
        do {
            let topic = try await topicFeature.updateTopic(
                currentUser,
                name,
                body.visibility,
                passwordHash
            )
            auditLogger.log("topic.update", req: req, metadata: [
                "actor_username": currentUser.username,
                "actor_role": currentUser.role.rawValue,
                "topic_name": topic.name,
                "visibility": topic.visibility.rawValue,
                "password_changed": body.password == nil ? "false" : "true",
                "has_password": topic.passwordHash == nil ? "false" : "true",
                "ip": req.clientIP,
            ])
            return try TopicResponse(topic)
        } catch {
            auditLogger.logError("topic.update", req: req, error: error, metadata: [
                "actor_username": currentUser.username,
                "actor_role": currentUser.role.rawValue,
                "topic_name": name,
                "visibility": body.visibility?.rawValue ?? "",
                "password_changed": body.password == nil ? "false" : "true",
                "ip": req.clientIP,
            ])
            throw error
        }
    }

    func delete(_ req: Request) async throws -> HTTPStatus {
        let currentUser = try req.user
        guard let name = req.parameters.get("name") else { throw Abort(.badRequest) }
        do {
            try await topicFeature.deleteTopic(currentUser, name)
            auditLogger.log("topic.delete", req: req, metadata: [
                "actor_username": currentUser.username,
                "actor_role": currentUser.role.rawValue,
                "topic_name": name,
                "ip": req.clientIP,
            ])
            return .noContent
        } catch {
            auditLogger.logError("topic.delete", req: req, error: error, metadata: [
                "actor_username": currentUser.username,
                "actor_role": currentUser.role.rawValue,
                "topic_name": name,
                "ip": req.clientIP,
            ])
            throw error
        }
    }

}

// MARK: - DTOs

struct TopicResponse: Content {
    let id: UUID
    let name: String
    let visibility: TopicVisibility
    let hasPassword: Bool
    let ownerUserID: UUID
    let createdAt: Date?

    init(_ topic: Topic) throws {
        self.id = try topic.requireID()
        self.name = topic.name
        self.visibility = topic.visibility
        self.hasPassword = topic.passwordHash != nil
        self.ownerUserID = topic.$owner.id
        self.createdAt = topic.createdAt
    }
}

struct TopicStatsResponse: Content {
    let subscriberCount: Int
    let messageCount: Int
    let lastMessageAt: Date?
    let deliveryStats: TopicDeliveryStatsResponse

    init(_ stats: TopicStats) {
        self.subscriberCount = stats.subscriberCount
        self.messageCount = stats.messageCount
        self.lastMessageAt = stats.lastMessageAt
        self.deliveryStats = TopicDeliveryStatsResponse(stats.deliveryStats)
    }
}

struct TopicDeliveryStatsResponse: Content {
    let pending: Int
    let ongoing: Int
    let delivered: Int
    let failed: Int

    init(_ stats: TopicDeliveryStats) {
        self.pending = stats.pending
        self.ongoing = stats.ongoing
        self.delivered = stats.delivered
        self.failed = stats.failed
    }
}

struct CreateTopicRequest: Content, Validatable {
    let name: String
    let visibility: TopicVisibility?
    let password: String?

    static func validations(_ validations: inout Validations) {
        validations.add("name", as: String.self, is: .count(3...) && .characterSet(.alphanumerics + .init(charactersIn: "-_.")))
    }
}

struct UpdateTopicRequest: Content {
    let visibility: TopicVisibility?
    let password: String?
}
