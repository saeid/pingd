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

    let listGlobalPermissions: @Sendable (
        _ currentUser: User
    ) async throws -> [Permission]

    let createPermission: @Sendable (
        _ currentUser: User,
        _ targetUsername: String,
        _ accessLevel: AccessLevel,
        _ topicPattern: String,
        _ expiresAt: Date?
    ) async throws -> Permission

    let createGlobalPermission: @Sendable (
        _ currentUser: User,
        _ accessLevel: AccessLevel,
        _ topicPattern: String,
        _ expiresAt: Date?
    ) async throws -> Permission

    let deletePermission: @Sendable (
        _ currentUser: User,
        _ permissionID: UUID
    ) async throws -> Void
}

extension PermissionFeature {
    static func live(
        permissionClient: PermissionClient,
        userClient: UserClient,
        defaultPermissionTTL: TimeInterval?,
        now: @escaping @Sendable () -> Date
    ) -> Self {
        @Sendable func resolveExpiresAt(_ explicit: Date?) -> Date? {
            if let explicit { return explicit }
            return defaultPermissionTTL.map { now().addingTimeInterval($0) }
        }

        return PermissionFeature(
            listPermissions: { currentUser, targetUsername in
                let targetID = try await userClient.getUserId(for: targetUsername)
                let currentUserID = try currentUser.requireID()
                guard currentUser.role == .admin || currentUserID == targetID else {
                    throw PermissionError.accessDenied
                }
                return try await permissionClient.listForUser(targetID)
            },
            listGlobalPermissions: { currentUser in
                guard currentUser.role == .admin else {
                    throw PermissionError.accessDenied
                }
                return try await permissionClient.listGlobal()
            },
            createPermission: { currentUser, targetUsername, accessLevel, topicPattern, expiresAt in
                guard currentUser.role == .admin else {
                    throw PermissionError.accessDenied
                }
                let targetID = try await userClient.getUserId(for: targetUsername)
                return try await permissionClient.create(targetID, .user, accessLevel, topicPattern, resolveExpiresAt(expiresAt))
            },
            createGlobalPermission: { currentUser, accessLevel, topicPattern, expiresAt in
                guard currentUser.role == .admin else {
                    throw PermissionError.accessDenied
                }
                return try await permissionClient.create(nil, .global, accessLevel, topicPattern, resolveExpiresAt(expiresAt))
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
