import Vapor

struct AuthController: RouteCollection, @unchecked Sendable {
    let authFeature: AuthFeature
    let tokenClient: TokenClient
    let deviceClient: DeviceClient
    let auditLogger: AuditLogger

    func boot(routes: any RoutesBuilder) throws {
        let auth = routes.grouped("auth")
        auth.post("login", use: login)
        auth.delete("logout", use: logout)
    }

    // MARK: - Handlers

    func login(_ req: Request) async throws -> LoginResponse {
        let body = try req.content.decode(LoginRequest.self)
        do {
            let user = try await authFeature.doBasicAuth(body.username, body.password)
            let userID = try user.requireID()
            let token: Token
            if let existing = try await tokenClient.findByLabel(userID, body.label) {
                token = existing
            } else {
                token = try await tokenClient.createToken(userID, body.label, nil)
            }
            auditLogger.log("login.success", req: req, metadata: [
                "username": body.username,
                "ip": req.clientIP,
            ])
            return LoginResponse(token: token.tokenHash, userID: user.id!, username: user.username)
        } catch {
            auditLogger.logError("login.failure", req: req, error: error, metadata: [
                "username": body.username,
                "ip": req.clientIP,
            ])
            throw error
        }
    }

    func me(_ req: Request) async throws -> UserResponse {
        UserResponse(try req.user)
    }

    func logout(_ req: Request) async throws -> HTTPStatus {
        guard let bearerToken = req.headers.bearerAuthorization?.token else {
            throw Abort(.unauthorized)
        }
        do {
            if let pushToken: String = req.query["pushToken"],
               let device = try await deviceClient.findByPushToken(pushToken) {
                let deviceID = try device.requireID()
                _ = try await deviceClient.update(deviceID, nil, nil, false)
            }
            try await tokenClient.revokeByHash(bearerToken)
            auditLogger.log("logout", req: req, metadata: [
                "ip": req.clientIP,
            ])
            return .noContent
        } catch {
            auditLogger.logError("logout", req: req, error: error, metadata: [
                "ip": req.clientIP,
            ])
            throw error
        }
    }

}

// MARK: - DTOs

struct LoginRequest: Content {
    let username: String
    let password: String
    let label: String
}

struct LoginResponse: Content {
    let token: String
    let userID: UUID
    let username: String
}
