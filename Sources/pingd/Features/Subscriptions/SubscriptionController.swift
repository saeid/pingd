import Vapor

struct SubscriptionController: RouteCollection, @unchecked Sendable {
    let subscriptionFeature: SubscriptionFeature

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
        guard let id = req.parameters.get("id", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        let body = try req.content.decode(SubscribeRequest.self)
        let sub = try await subscriptionFeature.subscribe(try req.user, id, body.topicName)
        return try SubscriptionResponse(sub)
    }

    func unsubscribe(_ req: Request) async throws -> HTTPStatus {
        guard let id = req.parameters.get("id", as: UUID.self),
              let topicName = req.parameters.get("topicName")
        else {
            throw Abort(.badRequest)
        }
        try await subscriptionFeature.unsubscribe(try req.user, id, topicName)
        return .noContent
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
