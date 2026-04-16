import Vapor

struct DispatchController: RouteCollection, @unchecked Sendable {
    let dispatchFeature: DispatchFeature
    let topicBroadcaster: TopicBroadcaster

    func boot(routes: any RoutesBuilder) throws {
        routes.get("messages", ":id", "deliveries", use: listDeliveries)
        routes.get("topics", ":name", "stream", use: stream)
    }

    func listDeliveries(_ req: Request) async throws -> [DeliveryResponse] {
        guard let id = req.parameters.get("id", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        let deliveries = try await dispatchFeature.listDeliveries(id)
        return try deliveries.map(DeliveryResponse.init)
    }

    /// SSE endpoint. Keeps connection open, pushes messages as they arrive.
    /// Response format: `data: {"title":"...","body":"..."}\n\n`
    func stream(_ req: Request) async throws -> Response {
        guard let name = req.parameters.get("name") else {
            throw Abort(.badRequest)
        }

        let (listenerID, payloadStream) = await topicBroadcaster.subscribe(topic: name)
        let broadcaster = topicBroadcaster

        let body = Response.Body(asyncStream: { writer in
            do {
                for try await payload in payloadStream {
                    let data = try JSONEncoder().encode(payload)
                    let line = "data: \(String(data: data, encoding: .utf8) ?? "{}")\n\n"
                    try await writer.write(.buffer(.init(string: line)))
                }
            } catch {
                // client disconnected or stream ended
            }
            await broadcaster.unsubscribe(topic: name, id: listenerID)
            try await writer.write(.end)
        })

        let response = Response(status: .ok, body: body)
        response.headers.replaceOrAdd(name: .contentType, value: "text/event-stream")
        response.headers.replaceOrAdd(name: .cacheControl, value: "no-cache")
        response.headers.replaceOrAdd(name: .connection, value: "keep-alive")
        return response
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
