import Fluent
import Vapor
import Foundation

struct PermissionClient {
    let listForUser: @Sendable (_ userID: UUID) async throws -> [Permission]
    let create: @Sendable (
        _ userID: UUID?,
        _ scope: PermissionScope,
        _ accessLevel: AccessLevel,
        _ topicPattern: String
    ) async throws -> Permission
    let delete: @Sendable (UUID) async throws -> Void
    let get: @Sendable (UUID) async throws -> Permission?
}

extension PermissionClient {
    static func live(app: Application) -> Self {
        PermissionClient(
            listForUser: { userID in
                try await Permission.query(on: app.db)
                    .filter(\.$user.$id == userID)
                    .all()
            },
            create: { userID, scope, accessLevel, topicPattern in
                let permission = Permission(
                    scope: scope,
                    accessLevel: accessLevel,
                    userId: userID,
                    topicPattern: topicPattern
                )
                try await permission.save(on: app.db)
                return permission
            },
            delete: { id in
                guard let permission = try await Permission.find(id, on: app.db) else { return }
                try await permission.delete(on: app.db)
            },
            get: { id in
                try await Permission.find(id, on: app.db)
            }
        )
    }

    static func mock(
        listForUser: @escaping @Sendable (UUID) async throws -> [Permission] = { _ in [] },
        create: @escaping @Sendable (UUID?, PermissionScope, AccessLevel, String) async throws -> Permission = { userID, scope, accessLevel, topicPattern in
            Permission(scope: scope, accessLevel: accessLevel, userId: userID, topicPattern: topicPattern)
        },
        delete: @escaping @Sendable (UUID) async throws -> Void = { _ in },
        get: @escaping @Sendable (UUID) async throws -> Permission? = { _ in nil }
    ) -> Self {
        PermissionClient(listForUser: listForUser, create: create, delete: delete, get: get)
    }
}
