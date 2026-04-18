import Vapor

struct TopicController: RouteCollection, @unchecked Sendable {
    let topicFeature: TopicFeature
    let authClient: AuthClient

    func boot(routes: any RoutesBuilder) throws {
        let topics = routes.grouped("topics")
        topics.get(use: list)
        topics.post(use: create)
        topics.get(":name", use: get)
        topics.patch(":name", use: update)
        topics.delete(":name", use: delete)
    }

    func list(_ req: Request) async throws -> [TopicResponse] {
        let topics = try await topicFeature.listTopics(req.optionalUser)
        return try topics.map(TopicResponse.init)
    }

    func create(_ req: Request) async throws -> TopicResponse {
        try CreateTopicRequest.validate(content: req)
        let body = try req.content.decode(CreateTopicRequest.self)
        let passwordHash: String?
        if let password = body.password, !password.isEmpty {
            passwordHash = try authClient.hashPassword(password)
        } else {
            passwordHash = nil
        }
        let topic = try await topicFeature.createTopic(
            try req.user,
            body.name,
            body.visibility ?? .protected,
            passwordHash
        )
        return try TopicResponse(topic)
    }

    func get(_ req: Request) async throws -> TopicResponse {
        guard let name = req.parameters.get("name") else { throw Abort(.badRequest) }
        let topic = try await topicFeature.getTopic(req.optionalUser, name, req.topicPassword)
        return try TopicResponse(topic)
    }

    func update(_ req: Request) async throws -> TopicResponse {
        guard let name = req.parameters.get("name") else { throw Abort(.badRequest) }
        let body = try req.content.decode(UpdateTopicRequest.self)
        let passwordHash: String?? = try body.password.map { password in
            if password.isEmpty {
                return nil
            }
            return try authClient.hashPassword(password)
        }
        let topic = try await topicFeature.updateTopic(
            try req.user,
            name,
            body.visibility,
            passwordHash
        )
        return try TopicResponse(topic)
    }

    func delete(_ req: Request) async throws -> HTTPStatus {
        guard let name = req.parameters.get("name") else { throw Abort(.badRequest) }
        try await topicFeature.deleteTopic(try req.user, name)
        return .noContent
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

struct CreateTopicRequest: Content, Validatable {
    let name: String
    let visibility: TopicVisibility?
    let password: String?

    static func validations(_ validations: inout Validations) {
        validations.add("name", as: String.self, is: .count(3...) && .characterSet(.alphanumerics + .init(charactersIn: "-_/")))
    }
}

struct UpdateTopicRequest: Content {
    let visibility: TopicVisibility?
    let password: String?
}
