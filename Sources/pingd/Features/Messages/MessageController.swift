import Vapor

struct MessageController: RouteCollection, @unchecked Sendable {
    let messageFeature: MessageFeature
    let now: @Sendable () -> Date

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
        self.id = try message.requireID()
        self.topicID = message.$topic.id
        self.time = message.time
        self.priority = message.priority
        self.tags = message.tags
        self.payload = message.payload
        self.createdAt = message.createdAt
    }
}

struct PublishMessageRequest: Content, Validatable {
    let priority: UInt8?
    let tags: [String]?
    let payload: MessagePayload

    static func validations(_ validations: inout Validations) {
        validations.add("payload", as: MessagePayload.self)
    }
}
