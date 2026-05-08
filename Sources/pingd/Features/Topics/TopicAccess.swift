import Foundation
import Vapor

enum TopicAccess {
    static func canRead(
        topic: Topic,
        currentUser: User?,
        topicToken: String?,
        topicShareClient: TopicShareClient,
        permissionClient: PermissionClient,
        now: Date = Date()
    ) async throws -> Bool {
        if currentUser?.role == .admin { return true }
        if try isOwner(topic: topic, currentUser: currentUser) { return true }

        if let level = try await resolveShareToken(
            topic: topic,
            topicToken: topicToken,
            topicShareClient: topicShareClient,
            now: now
        ) {
            return level == .readOnly || level == .readWrite
        }

        if let user = currentUser, user.role != .guest {
            let resolved = try await resolveAccess(
                user: user,
                topicName: topic.name,
                permissionClient: permissionClient,
                now: now
            )
            if let resolved {
                return resolved == .readOnly || resolved == .readWrite
            }
        }

        return topic.publicRead
    }

    static func canPublish(
        topic: Topic,
        currentUser: User?,
        topicToken: String?,
        topicShareClient: TopicShareClient,
        permissionClient: PermissionClient,
        now: Date = Date()
    ) async throws -> Bool {
        if currentUser?.role == .admin { return true }
        if try isOwner(topic: topic, currentUser: currentUser) { return true }

        if let level = try await resolveShareToken(
            topic: topic,
            topicToken: topicToken,
            topicShareClient: topicShareClient,
            now: now
        ) {
            return level == .writeOnly || level == .readWrite
        }

        if let user = currentUser, user.role != .guest {
            let resolved = try await resolveAccess(
                user: user,
                topicName: topic.name,
                permissionClient: permissionClient,
                now: now
            )
            if let resolved {
                return resolved == .writeOnly || resolved == .readWrite
            }
        }

        return topic.publicPublish
    }

    private static func isOwner(topic: Topic, currentUser: User?) throws -> Bool {
        guard let currentUser else { return false }
        return try currentUser.requireID() == topic.$owner.id
    }

    private static func resolveAccess(
        user: User,
        topicName: String,
        permissionClient: PermissionClient,
        now: Date
    ) async throws -> AccessLevel? {
        let userID = try user.requireID()
        let userPermissions = try await permissionClient.listForUser(userID)
        let globalPermissions = try await permissionClient.listGlobal()
        return PermissionResolver.resolve(
            permissions: userPermissions + globalPermissions,
            topicName: topicName,
            now: now
        )
    }

    private static func resolveShareToken(
        topic: Topic,
        topicToken: String?,
        topicShareClient: TopicShareClient,
        now: Date
    ) async throws -> AccessLevel? {
        guard let raw = topicToken,
              TopicShareTokenCodec.isWellFormed(raw)
        else { return nil }
        let hash = TopicShareTokenCodec.hash(raw)
        guard let share = try await topicShareClient.getByTokenHash(hash) else { return nil }
        guard try share.$topic.id == topic.requireID() else { return nil }
        if let expiresAt = share.expiresAt, expiresAt <= now { return nil }
        return share.accessLevel
    }
}
