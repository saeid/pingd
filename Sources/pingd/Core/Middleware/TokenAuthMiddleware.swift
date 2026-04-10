import Vapor

struct TokenAuthMiddleware: AsyncMiddleware {
    let tokenClient: TokenClient
    let now: @Sendable () -> Date

    func respond(to req: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        guard let bearerToken = req.headers.bearerAuthorization?.token else {
            throw Abort(.unauthorized)
        }
        let ip = req.headers.forwarded.first?.for ?? req.remoteAddress?.ipAddress ?? ""
        let user = try await tokenClient.markTokenUse(bearerToken, ip, now())
        req.storage[UserStorageKey.self] = user
        return try await next.respond(to: req)
    }
}

