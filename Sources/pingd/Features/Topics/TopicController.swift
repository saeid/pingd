import Vapor

struct TopicController: RouteCollection, @unchecked Sendable {
    let topicFeature: TopicFeature

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
        let topic = try await topicFeature.createTopic(
            try req.user,
            body.name,
            body.visibility ?? .protected,
            nil
        )
        return try TopicResponse(topic)
    }

    func get(_ req: Request) async throws -> TopicResponse {
        guard let name = req.parameters.get("name") else { throw Abort(.badRequest) }
        let topic = try await topicFeature.getTopic(req.optionalUser, name)
        return try TopicResponse(topic)
    }

    func update(_ req: Request) async throws -> TopicResponse {
        guard let name = req.parameters.get("name") else { throw Abort(.badRequest) }
        let body = try req.content.decode(UpdateTopicRequest.self)
        let topic = try await topicFeature.updateTopic(
            try req.user,
            name,
            body.visibility,
            body.password.map { Optional($0) } ?? .none
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
    let ownerUserID: UUID
    let createdAt: Date?

    init(_ topic: Topic) throws {
        self.id = try topic.requireID()
        self.name = topic.name
        self.visibility = topic.visibility
        self.ownerUserID = topic.$owner.id
        self.createdAt = topic.createdAt
    }
}

struct CreateTopicRequest: Content, Validatable {
    let name: String
    let visibility: TopicVisibility?

    static func validations(_ validations: inout Validations) {
        validations.add("name", as: String.self, is: .count(3...) && .characterSet(.alphanumerics + .init(charactersIn: "-_/")))
    }
}

struct UpdateTopicRequest: Content {
    let visibility: TopicVisibility?
    let password: String?
}
