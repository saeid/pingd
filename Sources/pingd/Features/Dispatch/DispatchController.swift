import Vapor

struct DispatchController: RouteCollection, @unchecked Sendable {
    let dispatchFeature: DispatchFeature
    let pushProvider: PushProvider

    func boot(routes: any RoutesBuilder) throws {
        routes.get("messages", ":id", "deliveries", use: listDeliveries)
        routes.post("apns", "push", use: relayPush)
    }

    func listDeliveries(_ req: Request) async throws -> [DeliveryResponse] {
        guard let id = req.parameters.get("id", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        let deliveries = try await dispatchFeature.listDeliveries(id)
        return try deliveries.map(DeliveryResponse.init)
    }

    func relayPush(_ req: Request) async throws -> HTTPStatus {
        let relayRequest = try req.content.decode(RelayPushRequest.self)
        let result = try await pushProvider.send(
            relayRequest.deviceToken,
            .apns,
            relayRequest.payload,
            relayRequest.metadata
        )

        guard result.success else {
            throw Abort(.badGateway, reason: result.error ?? "APNS delivery failed")
        }

        return .ok
    }
}

// MARK: - DTOs

struct DeliveryResponse: Content {
    let id: UUID
    let messageID: UUID
    let deviceID: UUID
    let status: DeliveryStatus
    let retryCount: UInt8
    let createdAt: Date?
    let updatedAt: Date?

    init(_ delivery: MessageDelivery) throws {
        self.id = try delivery.requireID()
        self.messageID = delivery.$message.id
        self.deviceID = delivery.$device.id
        self.status = delivery.status
        self.retryCount = delivery.retryCount
        self.createdAt = delivery.createdAt
        self.updatedAt = delivery.updatedAt
    }
}
