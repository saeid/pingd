import Vapor

struct OptionalTokenAuthMiddleware: AsyncMiddleware {
    let tokenClient: TokenClient
    let now: @Sendable () -> Date

    func respond(to req: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        if let bearerToken = req.headers.bearerAuthorization?.token {
            let ip = req.clientIP
            let user = try await tokenClient.markTokenUse(bearerToken, ip, now())
            req.storage[UserStorageKey.self] = user
        }
        return try await next.respond(to: req)
    }
}
