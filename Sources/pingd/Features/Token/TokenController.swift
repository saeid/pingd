import Vapor

struct TokenController: RouteCollection, @unchecked Sendable {
    let tokenFeature: TokenFeature

    func boot(routes: any RoutesBuilder) throws {
        let users = routes.grouped("users", ":username")
        users.get("tokens", use: list)
        users.post("tokens", use: create)
        routes.delete("tokens", ":id", use: revoke)
    }

    // MARK: - Handlers

    func list(_ req: Request) async throws -> [TokenResponse] {
        guard let username = req.parameters.get("username") else {
            throw Abort(.badRequest)
        }
        let tokens = try await tokenFeature.listUserTokens(try req.user, username)
        return tokens.map(TokenResponse.init)
    }

    func create(_ req: Request) async throws -> TokenResponse {
        guard let username = req.parameters.get("username") else {
            throw Abort(.badRequest)
        }
        let body = try req.content.decode(CreateTokenRequest.self)
        let token = try await tokenFeature.createUserToken(try req.user, username, body.label, body.expiresAt)
        return TokenResponse(token)
    }

    func revoke(_ req: Request) async throws -> HTTPStatus {
        guard let id = req.parameters.get("id", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        try await tokenFeature.revokeToken(try req.user, id)
        return .noContent
    }
}

// MARK: - DTOs

struct TokenResponse: Content {
    let id: UUID
    let label: String?
    let createdAt: Date?
    let expiresAt: Date?
    let lastUsedAt: Date?

    init(_ token: Token) {
        self.id = token.id!
        self.label = token.label
        self.createdAt = token.createdAt
        self.expiresAt = token.expiresAt
        self.lastUsedAt = token.lastUsedAt
    }
}

struct CreateTokenRequest: Content {
    let label: String?
    let expiresAt: Date?
}
