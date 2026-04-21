import Vapor

struct RequestLoggerMiddleware: AsyncMiddleware {
    func respond(to req: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        let start = Date()
        let response = try await next.respond(to: req)
        let durationMilliseconds = Int(Date().timeIntervalSince(start) * 1000)
        req.logger.info(
            "request.completed",
            metadata: [
                "method": .string(req.method.rawValue),
                "path": .string(req.url.path),
                "status": .stringConvertible(response.status.code),
                "duration_ms": .stringConvertible(durationMilliseconds),
            ]
        )
        return response
    }
}
