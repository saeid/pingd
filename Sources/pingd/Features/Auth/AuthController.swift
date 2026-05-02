import Vapor

struct AuthController: RouteCollection, @unchecked Sendable {
    let authFeature: AuthFeature
    let userClient: UserClient
    let authClient: AuthClient
    let tokenClient: TokenClient
    let deviceClient: DeviceClient
    let now: @Sendable () -> Date
    let auditLogger: AuditLogger

    func boot(routes: any RoutesBuilder) throws {
        let auth = routes.grouped("auth")
        auth.post("register", use: handleRegister)
        auth.post("guest", use: guest)
        auth.post("login", use: login)
        auth.delete("logout", use: logout)
    }

    // MARK: - Handlers

    func handleRegister(_ req: Request) async throws -> LoginResponse {
        guard req.application.appConfig.allowRegistration else {
            throw Abort(.forbidden, reason: "Registration is disabled")
        }
        try RegisterRequest.validate(content: req)
        let body = try req.content.decode(RegisterRequest.self)
        if try await userClient.getByUsername(body.username) != nil {
            throw UserError.userAlreadyExists
        }
        let passwordHash = try authClient.hashPassword(body.password)
        let user = try await userClient.create(body.username, passwordHash, .user)
        let userID = try user.requireID()
        let token = try await tokenClient.createToken(userID, body.label, nil)
        auditLogger.log("register", req: req, metadata: [
            "username": body.username,
            "ip": req.clientIP,
        ])
        return LoginResponse(token: token.tokenHash, userID: userID, username: user.username)
    }

    func login(_ req: Request) async throws -> LoginResponse {
        let body = try req.content.decode(LoginRequest.self)
        do {
            let user = try await authFeature.doBasicAuth(body.username, body.password)
            let userID = try user.requireID()
            let token: Token
            if let existing = try await tokenClient.findByLabel(userID, body.label, now()) {
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

    func guest(_ req: Request) async throws -> LoginResponse {
        let username = generateGuestUsername()
        let passwordHash = try authClient.hashPassword(UUID().uuidString)
        let user = try await userClient.create(username, passwordHash, .guest)
        let userID = try user.requireID()
        let token = try await tokenClient.createToken(
            userID,
            "guest",
            nil
        )
        auditLogger.log("guest.create", req: req, metadata: [
            "username": username,
            "ip": req.clientIP,
        ])
        return LoginResponse(token: token.tokenHash, userID: userID, username: user.username)
    }

    private func generateGuestUsername() -> String {
        let alphabet = Array("23456789abcdefghjkmnpqrstuvwxyz")
        let suffix = String((0..<6).compactMap { _ in alphabet.randomElement() })
        return "guest-\(suffix)"
    }

    func me(_ req: Request) async throws -> UserResponse {
        UserResponse(try req.user)
    }

    func logout(_ req: Request) async throws -> HTTPStatus {
        guard let bearerToken = req.headers.bearerAuthorization?.token else {
            throw Abort(.unauthorized)
        }
        do {
            let currentUser = try await tokenClient.markTokenUse(bearerToken, req.clientIP, now())
            let currentUserID = try currentUser.requireID()
            if let pushToken = req.headers.first(name: "X-Push-Token"),
               let device = try await deviceClient.findByPushToken(pushToken),
               device.$user.id == currentUserID {
                let deviceID = try device.requireID()
                _ = try await deviceClient.update(deviceID, nil, nil, false, nil)
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

struct RegisterRequest: Content, Validatable {
    let username: String
    let password: String
    let label: String?

    static func validations(_ validations: inout Validations) {
        validations.add("username", as: String.self, is: .count(3...) && .characterSet(.alphanumerics + .init(charactersIn: "-_")))
        validations.add("password", as: String.self, is: .count(6...))
    }
}
