import Vapor

enum TopicShareError: AbortError {
    case topicNotFound
    case shareNotFound
    case accessDenied
    case quotaExceeded(limit: Int)

    var status: HTTPResponseStatus {
        switch self {
        case .topicNotFound, .shareNotFound: .notFound
        case .accessDenied: .forbidden
        case .quotaExceeded: .tooManyRequests
        }
    }

    var reason: String {
        switch self {
        case .topicNotFound: "Topic not found"
        case .shareNotFound: "Share token not found"
        case .accessDenied: "Access denied"
        case let .quotaExceeded(limit): "Share token quota exceeded (max \(limit) per topic)"
        }
    }
}

struct TopicShareFeature {
    let listShares: @Sendable (
        _ currentUser: User,
        _ topicName: String
    ) async throws -> [TopicShareToken]

    let createShare: @Sendable (
        _ currentUser: User,
        _ topicName: String,
        _ label: String?,
        _ accessLevel: AccessLevel,
        _ expiresAt: Date?
    ) async throws -> (TopicShareToken, String)

    let rotateShare: @Sendable (
        _ currentUser: User,
        _ topicName: String,
        _ shareID: UUID
    ) async throws -> (TopicShareToken, String)

    let updateShare: @Sendable (
        _ currentUser: User,
        _ topicName: String,
        _ shareID: UUID,
        _ label: String??,
        _ accessLevel: AccessLevel?,
        _ expiresAt: Date??
    ) async throws -> TopicShareToken

    let deleteShare: @Sendable (
        _ currentUser: User,
        _ topicName: String,
        _ shareID: UUID
    ) async throws -> Void
}

extension TopicShareFeature {
    static func live(
        topicShareClient: TopicShareClient,
        topicClient: TopicClient,
        defaultShareTokenTTL: TimeInterval?,
        maxShareTokensPerTopic: Int?,
        now: @escaping @Sendable () -> Date
    ) -> Self {
        @Sendable func ownerOrAdminTopic(
            currentUser: User,
            topicName: String
        ) async throws -> Topic {
            guard let topic = try await topicClient.getByName(topicName) else {
                throw TopicShareError.topicNotFound
            }
            let userID = try currentUser.requireID()
            guard currentUser.role == .admin || topic.$owner.id == userID else {
                throw TopicShareError.accessDenied
            }
            return topic
        }

        return TopicShareFeature(
            listShares: { currentUser, topicName in
                let topic = try await ownerOrAdminTopic(currentUser: currentUser, topicName: topicName)
                return try await topicShareClient.listForTopic(topic.requireID())
            },
            createShare: { currentUser, topicName, label, accessLevel, expiresAt in
                let topic = try await ownerOrAdminTopic(currentUser: currentUser, topicName: topicName)
                let topicID = try topic.requireID()
                if let limit = maxShareTokensPerTopic {
                    let count = try await topicShareClient.listForTopic(topicID).count
                    if count >= limit {
                        throw TopicShareError.quotaExceeded(limit: limit)
                    }
                }
                let resolvedExpiresAt = expiresAt ?? defaultShareTokenTTL.map { now().addingTimeInterval($0) }
                let (raw, hash) = TopicShareTokenCodec.generate()
                let share = try await topicShareClient.create(
                    topicID,
                    hash,
                    label,
                    accessLevel,
                    currentUser.requireID(),
                    resolvedExpiresAt
                )
                return (share, raw)
            },
            rotateShare: { currentUser, topicName, shareID in
                let topic = try await ownerOrAdminTopic(currentUser: currentUser, topicName: topicName)
                guard let existing = try await topicShareClient.get(shareID) else {
                    throw TopicShareError.shareNotFound
                }
                guard try existing.$topic.id == topic.requireID() else {
                    throw TopicShareError.shareNotFound
                }
                let (raw, hash) = TopicShareTokenCodec.generate()
                guard let updated = try await topicShareClient.updateTokenHash(shareID, hash) else {
                    throw TopicShareError.shareNotFound
                }
                return (updated, raw)
            },
            updateShare: { currentUser, topicName, shareID, label, accessLevel, expiresAt in
                let topic = try await ownerOrAdminTopic(currentUser: currentUser, topicName: topicName)
                guard let existing = try await topicShareClient.get(shareID) else {
                    throw TopicShareError.shareNotFound
                }
                guard try existing.$topic.id == topic.requireID() else {
                    throw TopicShareError.shareNotFound
                }
                guard let updated = try await topicShareClient.update(shareID, label, accessLevel, expiresAt) else {
                    throw TopicShareError.shareNotFound
                }
                return updated
            },
            deleteShare: { currentUser, topicName, shareID in
                let topic = try await ownerOrAdminTopic(currentUser: currentUser, topicName: topicName)
                guard let existing = try await topicShareClient.get(shareID) else {
                    throw TopicShareError.shareNotFound
                }
                guard try existing.$topic.id == topic.requireID() else {
                    throw TopicShareError.shareNotFound
                }
                try await topicShareClient.delete(shareID)
            }
        )
    }
}
