import Vapor

struct TokenAuthMiddleware: AsyncMiddleware {
    let tokenClient: TokenClient
    let now: @Sendable () -> Date

    func respond(to req: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        guard let bearerToken = req.headers.bearerAuthorization?.token else {
            throw Abort(.unauthorized)
        }
        let ip = req.clientIP
        let user = try await tokenClient.markTokenUse(bearerToken, ip, now())
        req.storage[UserStorageKey.self] = user
        return try await next.respond(to: req)
    }
}
