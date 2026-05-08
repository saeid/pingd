import Vapor

struct PermissionController: RouteCollection, @unchecked Sendable {
    let permissionFeature: PermissionFeature
    let auditLogger: AuditLogger

    func boot(routes: any RoutesBuilder) throws {
        let permissions = routes.grouped("permissions")
        permissions.get(use: listGlobal)
        permissions.post(use: createGlobal)
        permissions.get(":username", use: list)
        permissions.post(":username", use: create)
        permissions.delete(":id", use: delete)
    }

    func listGlobal(_ req: Request) async throws -> [PermissionResponse] {
        let permissions = try await permissionFeature.listGlobalPermissions(req.user)
        return try permissions.map(PermissionResponse.init)
    }

    func createGlobal(_ req: Request) async throws -> PermissionResponse {
        let currentUser = try req.user
        try CreateGlobalPermissionRequest.validate(content: req)
        let body = try req.content.decode(CreateGlobalPermissionRequest.self)
        do {
            let permission = try await permissionFeature.createGlobalPermission(
                currentUser,
                body.accessLevel,
                body.topicPattern,
                body.expiresAt
            )
            auditLogger.log("permission.create", req: req, metadata: [
                "actor_username": currentUser.username,
                "actor_role": currentUser.role.rawValue,
                "scope": permission.scope.rawValue,
                "access_level": permission.accessLevel.rawValue,
                "topic_pattern": permission.topicPattern,
                "permission_id": permission.id?.uuidString ?? "unknown",
                "ip": req.clientIP,
            ])
            return try PermissionResponse(permission)
        } catch {
            auditLogger.logError("permission.create", req: req, error: error, metadata: [
                "actor_username": currentUser.username,
                "actor_role": currentUser.role.rawValue,
                "scope": PermissionScope.global.rawValue,
                "access_level": body.accessLevel.rawValue,
                "topic_pattern": body.topicPattern,
                "ip": req.clientIP,
            ])
            throw error
        }
    }

    func list(_ req: Request) async throws -> [PermissionResponse] {
        guard let username = req.parameters.get("username") else { throw Abort(.badRequest) }
        let permissions = try await permissionFeature.listPermissions(req.user, username)
        return try permissions.map(PermissionResponse.init)
    }

    func create(_ req: Request) async throws -> PermissionResponse {
        let currentUser = try req.user
        guard let username = req.parameters.get("username") else { throw Abort(.badRequest) }
        try CreatePermissionRequest.validate(content: req)
        let body = try req.content.decode(CreatePermissionRequest.self)
        do {
            let permission = try await permissionFeature.createPermission(
                currentUser,
                username,
                body.accessLevel,
                body.topicPattern,
                body.expiresAt
            )
            auditLogger.log("permission.create", req: req, metadata: [
                "actor_username": currentUser.username,
                "actor_role": currentUser.role.rawValue,
                "target_username": username,
                "scope": permission.scope.rawValue,
                "access_level": permission.accessLevel.rawValue,
                "topic_pattern": permission.topicPattern,
                "permission_id": permission.id?.uuidString ?? "unknown",
                "ip": req.clientIP,
            ])
            return try PermissionResponse(permission)
        } catch {
            auditLogger.logError("permission.create", req: req, error: error, metadata: [
                "actor_username": currentUser.username,
                "actor_role": currentUser.role.rawValue,
                "target_username": username,
                "scope": PermissionScope.user.rawValue,
                "access_level": body.accessLevel.rawValue,
                "topic_pattern": body.topicPattern,
                "ip": req.clientIP,
            ])
            throw error
        }
    }

    func delete(_ req: Request) async throws -> HTTPStatus {
        let currentUser = try req.user
        guard let id = req.parameters.get("id", as: UUID.self) else { throw Abort(.badRequest) }
        do {
            try await permissionFeature.deletePermission(currentUser, id)
            auditLogger.log("permission.delete", req: req, metadata: [
                "actor_username": currentUser.username,
                "actor_role": currentUser.role.rawValue,
                "permission_id": id.uuidString,
                "ip": req.clientIP,
            ])
            return .noContent
        } catch {
            auditLogger.logError("permission.delete", req: req, error: error, metadata: [
                "actor_username": currentUser.username,
                "actor_role": currentUser.role.rawValue,
                "permission_id": id.uuidString,
                "ip": req.clientIP,
            ])
            throw error
        }
    }

}

// MARK: - DTOs

struct PermissionResponse: Content {
    let id: UUID
    let userID: UUID?
    let scope: PermissionScope
    let accessLevel: AccessLevel
    let topicPattern: String
    let expiresAt: Date?
    let createdAt: Date?

    init(_ permission: Permission) throws {
        id = try permission.requireID()
        userID = permission.$user.id
        scope = permission.scope
        accessLevel = permission.accessLevel
        topicPattern = permission.topicPattern
        expiresAt = permission.expiresAt
        createdAt = permission.createdAt
    }
}

struct CreatePermissionRequest: Content, Validatable {
    let accessLevel: AccessLevel
    let topicPattern: String
    let expiresAt: Date?

    static func validations(_ validations: inout Validations) {
        validations.add("topicPattern", as: String.self, is: .count(1...) && .characterSet(.alphanumerics + .init(charactersIn: "-_.*>")))
    }
}

struct CreateGlobalPermissionRequest: Content, Validatable {
    let accessLevel: AccessLevel
    let topicPattern: String
    let expiresAt: Date?

    static func validations(_ validations: inout Validations) {
        validations.add("topicPattern", as: String.self, is: .count(1...) && .characterSet(.alphanumerics + .init(charactersIn: "-_.*>")))
    }
}
