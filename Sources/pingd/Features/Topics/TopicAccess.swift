import Vapor

/// `open` — anyone can read and publish.
/// `protected` — registered user/admin or password; guests need password.
/// `private` — owner/admin or explicit permission only.
enum TopicAccess {
    static func canRead(
        topic: Topic,
        currentUser: User?,
        topicPassword: String?,
        authClient: AuthClient,
        permissionClient: PermissionClient
    ) async throws -> Bool {
        if currentUser?.role == .admin { return true }

        if let user = currentUser, user.role != .guest {
            let resolved = try await resolveAccess(
                user: user,
                topicName: topic.name,
                permissionClient: permissionClient
            )
            if let resolved {
                return resolved != .deny && resolved != .writeOnly
            }
        }

        switch topic.visibility {
        case .open:
            return true
        case .protected:
            if currentUser?.role == .user { return true }
            return try hasMatchingPassword(
                topic: topic,
                topicPassword: topicPassword,
                authClient: authClient
            )
        case .private:
            if let user = currentUser {
                let ownerID = topic.$owner.id
                return try user.requireID() == ownerID
            }
            return false
        }
    }

    static func canPublish(
        topic: Topic,
        currentUser: User?,
        topicPassword: String?,
        authClient: AuthClient,
        permissionClient: PermissionClient
    ) async throws -> Bool {
        if currentUser?.role == .admin { return true }

        if let user = currentUser, user.role != .guest {
            let resolved = try await resolveAccess(
                user: user,
                topicName: topic.name,
                permissionClient: permissionClient
            )
            if let resolved {
                return resolved == .readWrite || resolved == .writeOnly
            }
        }

        switch topic.visibility {
        case .open:
            return true
        case .protected:
            if currentUser?.role == .user { return true }
            return try hasMatchingPassword(
                topic: topic,
                topicPassword: topicPassword,
                authClient: authClient
            )
        case .private:
            if let user = currentUser {
                let ownerID = topic.$owner.id
                return try user.requireID() == ownerID
            }
            return false
        }
    }

    private static func resolveAccess(
        user: User,
        topicName: String,
        permissionClient: PermissionClient
    ) async throws -> AccessLevel? {
        let userID = try user.requireID()
        let userPermissions = try await permissionClient.listForUser(userID)
        let globalPermissions = try await permissionClient.listGlobal()
        return PermissionResolver.resolve(permissions: userPermissions + globalPermissions, topicName: topicName)
    }

    private static func hasMatchingPassword(
        topic: Topic,
        topicPassword: String?,
        authClient: AuthClient
    ) throws -> Bool {
        guard let topicPassword, !topicPassword.isEmpty else {
            return false
        }
        guard let passwordHash = topic.passwordHash else {
            return false
        }
        return try authClient.verifyPassword(topicPassword, passwordHash)
    }
}
