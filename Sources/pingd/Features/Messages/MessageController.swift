import Vapor

struct MessageController: RouteCollection, @unchecked Sendable {
    let messageFeature: MessageFeature
    let now: @Sendable () -> Date
    let auditLogger: AuditLogger

    func boot(routes: any RoutesBuilder) throws {
        let messages = routes.grouped("topics", ":name", "messages")
        messages.get(use: list)
        messages.post(use: publish)
    }

    func list(_ req: Request) async throws -> [MessageResponse] {
        guard let name = req.parameters.get("name") else { throw Abort(.badRequest) }
        let messages = try await messageFeature.listMessages(req.optionalUser, name, req.topicToken, now())
        return try messages.map(MessageResponse.init)
    }

    func publish(_ req: Request) async throws -> MessageResponse {
        guard let name = req.parameters.get("name") else { throw Abort(.badRequest) }
        try PublishMessageRequest.validate(content: req)
        let body = try req.content.decode(PublishMessageRequest.self)
        try body.validateTags()
        try body.validateTTL()
        do {
            let message = try await messageFeature.publishMessage(
                req.optionalUser,
                name,
                req.topicToken,
                body.priority ?? 2,
                body.tags,
                body.payload,
                now(),
                body.ttl
            )
            return try MessageResponse(message)
        } catch {
            auditLogger.logError("message.publish", req: req, error: error, metadata: [
                "actor_username": (try? req.user)?.username ?? "anonymous",
                "topic_name": name,
                "ip": req.clientIP,
            ])
            throw error
        }
    }
}

// MARK: - DTOs

struct MessageResponse: Content {
    let id: UUID
    let topicID: UUID
    let time: Date
    let priority: UInt8
    let tags: [String]?
    let payload: MessagePayload
    let expiresAt: Date?
    let createdAt: Date?

    init(_ message: Message) throws {
        id = try message.requireID()
        topicID = message.$topic.id
        time = message.time
        priority = message.priority
        tags = message.tags
        payload = message.payload
        expiresAt = message.expiresAt
        createdAt = message.createdAt
    }
}

struct PublishMessageRequest: Content, Validatable {
    let priority: UInt8?
    let tags: [String]?
    let payload: MessagePayload
    let ttl: Int?

    init(priority: UInt8?, tags: [String]?, payload: MessagePayload, ttl: Int? = nil) {
        self.priority = priority
        self.tags = tags
        self.payload = payload
        self.ttl = ttl
    }

    static func validations(_ validations: inout Validations) {
        validations.add("payload", as: MessagePayload.self)
    }

    func validateTags() throws {
        guard let tags else { return }
        try MessageTagValidator.validate(tags)
    }

    func validateTTL() throws {
        guard let ttl else { return }
        guard ttl > 0 else {
            throw Abort(.badRequest, reason: "ttl must be positive")
        }
        guard ttl <= 60 * 60 * 24 * 30 else {
            throw Abort(.badRequest, reason: "ttl must be <= 30 days")
        }
    }
}
