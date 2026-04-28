import Foundation
import Vapor

struct WebhookRateLimitMiddleware: AsyncMiddleware {
    let rateLimiter: RateLimiter
    let now: @Sendable () -> Date

    func respond(to req: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        let config = req.application.appConfig.webhookRateLimit
        guard config.isEnabled else {
            return try await next.respond(to: req)
        }

        let ip = req.clientIP
        let ipDecision = await rateLimiter.check(
            key: "webhook-ip:\(ip)",
            limit: config.perIPCount,
            now: now()
        )
        if !ipDecision.isAllowed {
            return tooManyRequests(retryAfter: ipDecision.retryAfterSeconds)
        }

        if let token = req.parameters.get("token") {
            let tokenKey = "webhook-token:\(WebhookFeature.tokenHash(token))"
            let tokenDecision = await rateLimiter.check(
                key: tokenKey,
                limit: config.perTokenCount,
                now: now()
            )
            if !tokenDecision.isAllowed {
                return tooManyRequests(retryAfter: tokenDecision.retryAfterSeconds)
            }
        }

        return try await next.respond(to: req)
    }

    private func tooManyRequests(retryAfter: Int?) -> Response {
        let response = Response(status: .tooManyRequests)
        response.body = .init(string: "Too many requests")
        if let retryAfter {
            response.headers.replaceOrAdd(name: .retryAfter, value: String(retryAfter))
        }
        return response
    }
}
