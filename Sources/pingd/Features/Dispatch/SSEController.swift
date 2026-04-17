import Vapor

struct SSEController: RouteCollection, @unchecked Sendable {
    let topicBroadcaster: TopicBroadcaster
    let topicFeature: TopicFeature

    func boot(routes: any RoutesBuilder) throws {
        routes.get("topics", ":name", "stream", use: stream)
    }

    func stream(_ req: Request) async throws -> Response {
        guard let name = req.parameters.get("name") else {
            throw Abort(.badRequest)
        }

        _ = try await topicFeature.getTopic(req.optionalUser, name)

        let (listenerID, payloadStream) = await topicBroadcaster.subscribe(topic: name)
        let broadcaster = topicBroadcaster

        let body = Response.Body(asyncStream: { writer in
            do {
                try await writer.write(.buffer(.init(string: ": connected\n\n")))
                for try await payload in payloadStream {
                    let data = try JSONEncoder().encode(payload)
                    let line = "data: \(String(data: data, encoding: .utf8) ?? "{}")\n\n"
                    try await writer.write(.buffer(.init(string: line)))
                }
            } catch {
                // client disconnected
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
