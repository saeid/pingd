import Vapor

enum PermissionError: AbortError {
    case notFound
    case accessDenied

    var status: HTTPResponseStatus {
        switch self {
        case .notFound: .notFound
        case .accessDenied: .forbidden
        }
    }

    var reason: String {
        switch self {
        case .notFound: "Permission not found"
        case .accessDenied: "Access denied"
        }
    }
}

struct PermissionFeature {
    let listPermissions: @Sendable (
        _ currentUser: User,
        _ targetUsername: String
    ) async throws -> [Permission]

    let createPermission: @Sendable (
        _ currentUser: User,
        _ targetUsername: String,
        _ scope: PermissionScope,
        _ accessLevel: AccessLevel,
        _ topicPattern: String
    ) async throws -> Permission

    let deletePermission: @Sendable (
        _ currentUser: User,
        _ permissionID: UUID
    ) async throws -> Void
}

extension PermissionFeature {
    static func live(permissionClient: PermissionClient, userClient: UserClient) -> Self {
        PermissionFeature(
            listPermissions: { currentUser, targetUsername in
                let targetID = try await userClient.getUserId(for: targetUsername)
                let currentUserID = try currentUser.requireID()
                guard currentUser.role == .admin || currentUserID == targetID else {
                    throw PermissionError.accessDenied
                }
                return try await permissionClient.listForUser(targetID)
            },
            createPermission: { currentUser, targetUsername, scope, accessLevel, topicPattern in
                guard currentUser.role == .admin else {
                    throw PermissionError.accessDenied
                }
                let targetID = try await userClient.getUserId(for: targetUsername)
                return try await permissionClient.create(targetID, scope, accessLevel, topicPattern)
            },
            deletePermission: { currentUser, permissionID in
                guard currentUser.role == .admin else {
                    throw PermissionError.accessDenied
                }
                guard try await permissionClient.get(permissionID) != nil else {
                    throw PermissionError.notFound
                }
                try await permissionClient.delete(permissionID)
            }
        )
    }
}
