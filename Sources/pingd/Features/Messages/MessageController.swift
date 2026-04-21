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
        let messages = try await messageFeature.listMessages(req.optionalUser, name, req.topicPassword)
        return try messages.map(MessageResponse.init)
    }

    func publish(_ req: Request) async throws -> MessageResponse {
        guard let name = req.parameters.get("name") else { throw Abort(.badRequest) }
        try PublishMessageRequest.validate(content: req)
        let body = try req.content.decode(PublishMessageRequest.self)
        try body.validateTags()
        do {
            let message = try await messageFeature.publishMessage(
                req.optionalUser,
                name,
                req.topicPassword,
                body.priority ?? 3,
                body.tags,
                body.payload,
                now()
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
    let createdAt: Date?

    init(_ message: Message) throws {
        id = try message.requireID()
        topicID = message.$topic.id
        time = message.time
        priority = message.priority
        tags = message.tags
        payload = message.payload
        createdAt = message.createdAt
    }
}

struct PublishMessageRequest: Content, Validatable {
    let priority: UInt8?
    let tags: [String]?
    let payload: MessagePayload

    static func validations(_ validations: inout Validations) {
        validations.add("payload", as: MessagePayload.self)
    }

    func validateTags() throws {
        guard let tags else { return }
        let allowedCharacters = CharacterSet.alphanumerics.union(.init(charactersIn: "-_"))

        guard tags.count <= 10 else {
            throw Abort(.badRequest, reason: "Maximum 10 tags allowed")
        }
        for tag in tags {
            guard tag.count >= 1, tag.count <= 30 else {
                throw Abort(.badRequest, reason: "Tag must be 1-30 characters")
            }
            guard tag.unicodeScalars.allSatisfy({ allowedCharacters.contains($0) }) else {
                throw Abort(.badRequest, reason: "Tag '\(tag)' contains invalid characters. Only alphanumeric, dash, underscore allowed")
            }
        }
    }
}
