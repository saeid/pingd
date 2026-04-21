import Vapor

struct RateLimitMiddleware: AsyncMiddleware {
    let rateLimiter: RateLimiter
    let now: @Sendable () -> Date

    func respond(to req: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        let config = req.application.appConfig.rateLimit
        guard config.isEnabled else {
            return try await next.respond(to: req)
        }

        let decision = await rateLimiter.check(
            key: req.clientIP,
            limit: config.count,
            now: now()
        )

        guard decision.isAllowed else {
            let response = Response(status: .tooManyRequests)
            response.body = .init(string: "Too many requests")
            if let retryAfterSeconds = decision.retryAfterSeconds {
                response.headers.replaceOrAdd(name: .retryAfter, value: String(retryAfterSeconds))
            }
            return response
        }

        return try await next.respond(to: req)
    }

}
