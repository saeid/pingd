import Foundation
import Vapor

struct PublishRateLimitMiddleware: AsyncMiddleware {
    let rateLimiter: RateLimiter
    let now: @Sendable () -> Date

    func respond(to req: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        guard req.method == .POST else {
            return try await next.respond(to: req)
        }
        let config = req.application.appConfig

        if let user = req.optionalUser, let limit = config.publishRateLimitPerUserPerMin {
            let userID = (try? user.requireID().uuidString) ?? user.username
            let decision = await rateLimiter.check(
                key: "publish-user:\(userID)",
                limit: limit,
                now: now()
            )
            if !decision.isAllowed {
                return tooManyRequests(retryAfter: decision.retryAfterSeconds)
            }
        } else if req.optionalUser == nil, let limit = config.anonPublishRateLimitPerIPPerMin {
            let decision = await rateLimiter.check(
                key: "publish-ip:\(req.clientIP)",
                limit: limit,
                now: now()
            )
            if !decision.isAllowed {
                return tooManyRequests(retryAfter: decision.retryAfterSeconds)
            }
        }

        return try await next.respond(to: req)
    }

    private func tooManyRequests(retryAfter: Int?) -> Response {
        let response = Response(status: .tooManyRequests)
        response.body = .init(string: "Too many publish requests")
        if let retryAfter {
            response.headers.replaceOrAdd(name: .retryAfter, value: String(retryAfter))
        }
        return response
    }
}
