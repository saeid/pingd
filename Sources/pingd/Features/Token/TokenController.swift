import Vapor

struct TokenController: RouteCollection, @unchecked Sendable {
    let tokenFeature: TokenFeature
    let auditLogger: AuditLogger

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
        let currentUser = try req.user
        let tokens = try await tokenFeature.listUserTokens(currentUser, username)
        let showFullToken = currentUser.role == .admin
        return tokens.map { TokenResponse($0, showFullToken: showFullToken) }
    }

    func create(_ req: Request) async throws -> TokenResponse {
        let currentUser = try req.user
        guard let username = req.parameters.get("username") else {
            throw Abort(.badRequest)
        }
        let body = try req.content.decode(CreateTokenRequest.self)
        do {
            let token = try await tokenFeature.createUserToken(currentUser, username, body.label, body.expiresAt)
            auditLogger.log("token.create", req: req, metadata: [
                "actor_username": currentUser.username,
                "actor_role": currentUser.role.rawValue,
                "target_username": username,
                "token_id": token.id?.uuidString ?? "unknown",
                "label": token.label ?? "",
                "ip": req.clientIP,
            ])
            return TokenResponse(token, showFullToken: true)
        } catch {
            auditLogger.logError("token.create", req: req, error: error, metadata: [
                "actor_username": currentUser.username,
                "actor_role": currentUser.role.rawValue,
                "target_username": username,
                "label": body.label ?? "",
                "ip": req.clientIP,
            ])
            throw error
        }
    }

    func revoke(_ req: Request) async throws -> HTTPStatus {
        let currentUser = try req.user
        guard let id = req.parameters.get("id", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        let activeToken = req.headers.bearerAuthorization?.token
        do {
            try await tokenFeature.revokeToken(currentUser, id, activeToken)
            auditLogger.log("token.revoke", req: req, metadata: [
                "actor_username": currentUser.username,
                "actor_role": currentUser.role.rawValue,
                "token_id": id.uuidString,
                "ip": req.clientIP,
            ])
            return .noContent
        } catch {
            auditLogger.logError("token.revoke", req: req, error: error, metadata: [
                "actor_username": currentUser.username,
                "actor_role": currentUser.role.rawValue,
                "token_id": id.uuidString,
                "ip": req.clientIP,
            ])
            throw error
        }
    }

}

// MARK: - DTOs

struct TokenResponse: Content {
    let id: UUID
    let token: String
    let label: String?
    let createdAt: Date?
    let expiresAt: Date?
    let lastUsedAt: Date?

    init(_ token: Token, showFullToken: Bool = false) {
        self.id = token.id!
        self.token = showFullToken ? token.tokenHash : "pgd_****\(token.tokenHash.suffix(4))"
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
