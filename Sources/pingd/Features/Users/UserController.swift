import Vapor

struct UserController: RouteCollection, @unchecked Sendable {
    let userFeature: UserFeature
    let authClient: AuthClient

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
        try CreateUserRequest.validate(content: req)
        let body = try req.content.decode(CreateUserRequest.self)
        let passwordHash = try authClient.hashPassword(body.password)
        let created = try await userFeature.createUser(try req.user, body.username, passwordHash, body.role)
        return UserResponse(created)
    }

    func get(_ req: Request) async throws -> UserResponse {
        guard let username = req.parameters.get("username") else {
            throw Abort(.badRequest)
        }
        let fetched = try await userFeature.getUser(try req.user, username)
        return UserResponse(fetched)
    }

    func update(_ req: Request) async throws -> UserResponse {
        guard let username = req.parameters.get("username") else {
            throw Abort(.badRequest)
        }
        try UpdateUserRequest.validate(content: req)
        let body = try req.content.decode(UpdateUserRequest.self)
        let passwordHash = try body.password.map { try authClient.hashPassword($0) }
        let updated = try await userFeature.updateUser(try req.user, username, passwordHash, body.role)
        return UserResponse(updated)
    }

    func delete(_ req: Request) async throws -> HTTPStatus {
        guard let username = req.parameters.get("username") else {
            throw Abort(.badRequest)
        }
        try await userFeature.deleteUser(try req.user, username)
        return .noContent
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
