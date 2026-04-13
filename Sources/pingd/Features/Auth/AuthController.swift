import Vapor

struct AuthController: RouteCollection, @unchecked Sendable {
    let authFeature: AuthFeature
    let tokenClient: TokenClient

    func boot(routes: any RoutesBuilder) throws {
        let auth = routes.grouped("auth")
        auth.post("login", use: login)
        auth.delete("logout", use: logout)
    }

    // MARK: - Handlers

    func login(_ req: Request) async throws -> LoginResponse {
        let body = try req.content.decode(LoginRequest.self)
        let user = try await authFeature.doBasicAuth(body.username, body.password)
        let token = try await tokenClient.createToken(user.requireID(), body.label, nil)
        return LoginResponse(token: token.tokenHash, userID: user.id!, username: user.username)
    }

    func me(_ req: Request) async throws -> UserResponse {
        UserResponse(try req.user)
    }

    func logout(_ req: Request) async throws -> HTTPStatus {
        guard let bearerToken = req.headers.bearerAuthorization?.token else {
            throw Abort(.unauthorized)
        }
        try await tokenClient.revokeByHash(bearerToken)
        return .noContent
    }
}

// MARK: - DTOs

struct LoginRequest: Content {
    let username: String
    let password: String
    let label: String?
}

struct LoginResponse: Content {
    let token: String
    let userID: UUID
    let username: String
}
