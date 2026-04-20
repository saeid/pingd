import Vapor

struct PermissionController: RouteCollection, @unchecked Sendable {
    let permissionFeature: PermissionFeature

    func boot(routes: any RoutesBuilder) throws {
        let permissions = routes.grouped("permissions")
        permissions.get(use: listGlobal)
        permissions.post(use: createGlobal)
        permissions.get(":username", use: list)
        permissions.post(":username", use: create)
        permissions.delete(":id", use: delete)
    }

    func listGlobal(_ req: Request) async throws -> [PermissionResponse] {
        let permissions = try await permissionFeature.listGlobalPermissions(try req.user)
        return try permissions.map(PermissionResponse.init)
    }

    func createGlobal(_ req: Request) async throws -> PermissionResponse {
        try CreateGlobalPermissionRequest.validate(content: req)
        let body = try req.content.decode(CreateGlobalPermissionRequest.self)
        let permission = try await permissionFeature.createGlobalPermission(
            try req.user,
            body.accessLevel,
            body.topicPattern
        )
        return try PermissionResponse(permission)
    }

    func list(_ req: Request) async throws -> [PermissionResponse] {
        guard let username = req.parameters.get("username") else { throw Abort(.badRequest) }
        let permissions = try await permissionFeature.listPermissions(try req.user, username)
        return try permissions.map(PermissionResponse.init)
    }

    func create(_ req: Request) async throws -> PermissionResponse {
        guard let username = req.parameters.get("username") else { throw Abort(.badRequest) }
        try CreatePermissionRequest.validate(content: req)
        let body = try req.content.decode(CreatePermissionRequest.self)
        let permission = try await permissionFeature.createPermission(
            try req.user,
            username,
            body.accessLevel,
            body.topicPattern
        )
        return try PermissionResponse(permission)
    }

    func delete(_ req: Request) async throws -> HTTPStatus {
        guard let id = req.parameters.get("id", as: UUID.self) else { throw Abort(.badRequest) }
        try await permissionFeature.deletePermission(try req.user, id)
        return .noContent
    }
}

// MARK: - DTOs

struct PermissionResponse: Content {
    let id: UUID
    let userID: UUID?
    let scope: PermissionScope
    let accessLevel: AccessLevel
    let topicPattern: String
    let createdAt: Date?

    init(_ permission: Permission) throws {
        self.id = try permission.requireID()
        self.userID = permission.$user.id
        self.scope = permission.scope
        self.accessLevel = permission.accessLevel
        self.topicPattern = permission.topicPattern
        self.createdAt = permission.createdAt
    }
}

struct CreatePermissionRequest: Content, Validatable {
    let accessLevel: AccessLevel
    let topicPattern: String

    static func validations(_ validations: inout Validations) {
        validations.add("topicPattern", as: String.self, is: .count(1...) && .characterSet(.alphanumerics + .init(charactersIn: "-_.*>")))
    }
}

struct CreateGlobalPermissionRequest: Content, Validatable {
    let accessLevel: AccessLevel
    let topicPattern: String

    static func validations(_ validations: inout Validations) {
        validations.add("topicPattern", as: String.self, is: .count(1...) && .characterSet(.alphanumerics + .init(charactersIn: "-_.*>")))
    }
}
