import Vapor

struct UserController: RouteCollection, @unchecked Sendable {
    let userFeature: UserFeature
    let authClient: AuthClient
    let auditLogger: AuditLogger

    func boot(routes: any RoutesBuilder) throws {
        let users = routes.grouped("users")
        users.get(use: list)
        users.post(use: create)
        users.get(":username", use: get)
        users.patch(":username", use: update)
        users.delete(":username", use: delete)
    }

    // MARK: - Handlers

    func list(_ req: Request) async throws -> [UserResponse] {
        let users = try await userFeature.listUsers(req.user)
        return users.map(UserResponse.init)
    }

    func create(_ req: Request) async throws -> UserResponse {
        let currentUser = try req.user
        try CreateUserRequest.validate(content: req)
        let body = try req.content.decode(CreateUserRequest.self)
        let passwordHash = try authClient.hashPassword(body.password)
        do {
            let created = try await userFeature.createUser(currentUser, body.username, passwordHash, body.role)
            auditLogger.log("user.create", req: req, metadata: [
                "actor_username": currentUser.username,
                "actor_role": currentUser.role.rawValue,
                "target_username": created.username,
                "target_role": created.role.rawValue,
                "ip": req.clientIP,
            ])
            return UserResponse(created)
        } catch {
            auditLogger.logError("user.create", req: req, error: error, metadata: [
                "actor_username": currentUser.username,
                "actor_role": currentUser.role.rawValue,
                "target_username": body.username,
                "target_role": body.role?.rawValue ?? UserRole.user.rawValue,
                "ip": req.clientIP,
            ])
            throw error
        }
    }

    func get(_ req: Request) async throws -> UserResponse {
        guard let username = req.parameters.get("username") else {
            throw Abort(.badRequest)
        }
        let fetched = try await userFeature.getUser(try req.user, username)
        return UserResponse(fetched)
    }

    func update(_ req: Request) async throws -> UserResponse {
        let currentUser = try req.user
        guard let username = req.parameters.get("username") else {
            throw Abort(.badRequest)
        }
        try UpdateUserRequest.validate(content: req)
        let body = try req.content.decode(UpdateUserRequest.self)
        let passwordHash = try body.password.map { try authClient.hashPassword($0) }
        do {
            let updated = try await userFeature.updateUser(currentUser, username, passwordHash, body.role)
            auditLogger.log("user.update", req: req, metadata: [
                "actor_username": currentUser.username,
                "actor_role": currentUser.role.rawValue,
                "target_username": updated.username,
                "target_role": updated.role.rawValue,
                "password_changed": passwordHash == nil ? "false" : "true",
                "ip": req.clientIP,
            ])
            return UserResponse(updated)
        } catch {
            auditLogger.logError("user.update", req: req, error: error, metadata: [
                "actor_username": currentUser.username,
                "actor_role": currentUser.role.rawValue,
                "target_username": username,
                "target_role": body.role?.rawValue ?? "",
                "password_changed": passwordHash == nil ? "false" : "true",
                "ip": req.clientIP,
            ])
            throw error
        }
    }

    func delete(_ req: Request) async throws -> HTTPStatus {
        let currentUser = try req.user
        guard let username = req.parameters.get("username") else {
            throw Abort(.badRequest)
        }
        do {
            try await userFeature.deleteUser(currentUser, username)
            auditLogger.log("user.delete", req: req, metadata: [
                "actor_username": currentUser.username,
                "actor_role": currentUser.role.rawValue,
                "target_username": username,
                "ip": req.clientIP,
            ])
            return .noContent
        } catch {
            auditLogger.logError("user.delete", req: req, error: error, metadata: [
                "actor_username": currentUser.username,
                "actor_role": currentUser.role.rawValue,
                "target_username": username,
                "ip": req.clientIP,
            ])
            throw error
        }
    }

}

// MARK: - DTOs

struct UserResponse: Content {
    let id: UUID
    let username: String
    let role: UserRole
    let createdAt: Date?

    init(_ user: User) {
        self.id = user.id!
        self.username = user.username
        self.role = user.role
        self.createdAt = user.createdAt
    }
}

struct CreateUserRequest: Content, Validatable {
    let username: String
    let password: String
    let role: UserRole?

    static func validations(_ validations: inout Validations) {
        validations.add("username", as: String.self, is: .count(3...) && .characterSet(.alphanumerics + .init(charactersIn: "-_")))
        validations.add("password", as: String.self, is: .count(6...))
    }
}

struct UpdateUserRequest: Content, Validatable {
    let password: String?
    let role: UserRole?

    static func validations(_ validations: inout Validations) {
        validations.add("password", as: String.self, is: .count(6...), required: false)
    }
}
