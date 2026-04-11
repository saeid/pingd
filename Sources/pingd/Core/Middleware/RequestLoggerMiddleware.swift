import Vapor

struct RequestLoggerMiddleware: AsyncMiddleware {
    func respond(to req: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        let start = Date()
        let response = try await next.respond(to: req)
        let duration = Int(Date().timeIntervalSince(start) * 1000)
        req.logger.info("\(req.method) \(req.url.path) \(response.status.code) \(duration)ms")
        return response
    }
}
