import Foundation
import Vapor

enum TopicError: AbortError {
    case notFound
    case nameTaken
    case nameReserved
    case quotaExceeded(limit: Int)
    case accessDenied

    var status: HTTPResponseStatus {
        switch self {
        case .notFound: .notFound
        case .nameTaken, .nameReserved: .badRequest
        case .quotaExceeded: .tooManyRequests
        case .accessDenied: .forbidden
        }
    }

    var reason: String {
        switch self {
        case .notFound: "Topic not found"
        case .nameTaken: "Topic name already taken"
        case .nameReserved: "Topic name is reserved"
        case let .quotaExceeded(limit): "Topic quota exceeded (max \(limit) per user)"
        case .accessDenied: "Access denied"
        }
    }
}

struct TopicFeature {
    /// currentUser nil = anonymous
    let listTopics: @Sendable (_ currentUser: User?) async throws -> [Topic]

    let topicStats: @Sendable (
        _ currentUser: User,
        _ name: String
    ) async throws -> TopicStats

    let getTopic: @Sendable (
        _ currentUser: User?,
        _ name: String,
        _ topicToken: String?
    ) async throws -> Topic

    let createTopic: @Sendable (
        _ currentUser: User,
        _ name: String,
        _ publicRead: Bool,
        _ publicPublish: Bool
    ) async throws -> Topic

    let updateTopic: @Sendable (
        _ currentUser: User,
        _ name: String,
        _ publicRead: Bool?,
        _ publicPublish: Bool?
    ) async throws -> Topic

    let deleteTopic: @Sendable (
        _ currentUser: User,
        _ name: String
    ) async throws -> Void
}

extension TopicFeature {
    static func live(
        topicClient: TopicClient,
        topicShareClient: TopicShareClient,
        permissionClient: PermissionClient,
        messageClient: MessageClient,
        subscriptionClient: SubscriptionClient,
        dispatchClient: DispatchClient,
        reservedTopicNames: Set<String>,
        maxTopicsPerUser: Int?,
        now: @escaping @Sendable () -> Date
    ) -> Self {
        TopicFeature(
            listTopics: { currentUser in
                let all = try await topicClient.list()

                guard let user = currentUser else {
                    return all.filter { $0.publicRead }
                }
                if user.role == .admin { return all }
                if user.role == .guest {
                    return all.filter { $0.publicRead }
                }

                let userID = try user.requireID()
                let userPermissions = try await permissionClient.listForUser(userID)
                let globalPermissions = try await permissionClient.listGlobal()
                let allPermissions = userPermissions + globalPermissions
                let currentDate = now()

                return all.filter { topic in
                    if topic.$owner.id == userID { return true }
                    let resolved = PermissionResolver.resolve(
                        permissions: allPermissions,
                        topicName: topic.name,
                        now: currentDate
                    )
                    if let resolved {
                        return resolved == .readOnly || resolved == .readWrite
                    }
                    return topic.publicRead
                }
            },
            topicStats: { currentUser, name in
                guard currentUser.role == .admin else {
                    throw TopicError.accessDenied
                }
                guard let topic = try await topicClient.getByName(name) else {
                    throw TopicError.notFound
                }

                let topicID = try topic.requireID()
                async let subscriberCount = subscriptionClient.countForTopic(topicID)
                async let messageCount = messageClient.count(topicID)
                async let lastMessage = messageClient.lastMessage(topicID)
                async let deliveryStats = dispatchClient.statsForTopic(topicID)

                let latestMessage = try await lastMessage
                let deliveries = try await deliveryStats

                return TopicStats(
                    subscriberCount: try await subscriberCount,
                    messageCount: try await messageCount,
                    lastMessageAt: latestMessage?.time,
                    deliveryStats: TopicDeliveryStats(deliveries)
                )
            },
            getTopic: { currentUser, name, topicToken in
                guard let topic = try await topicClient.getByName(name) else {
                    throw TopicError.notFound
                }
                if try await !TopicAccess.canRead(
                    topic: topic,
                    currentUser: currentUser,
                    topicToken: topicToken,
                    topicShareClient: topicShareClient,
                    permissionClient: permissionClient,
                    now: now()
                ) {
                    throw TopicError.accessDenied
                }
                return topic
            },
            createTopic: { currentUser, name, publicRead, publicPublish in
                guard currentUser.role != .guest else {
                    throw TopicError.accessDenied
                }
                if reservedTopicNames.contains(name.lowercased()) {
                    throw TopicError.nameReserved
                }
                if try await topicClient.getByName(name) != nil {
                    throw TopicError.nameTaken
                }
                let ownerID = try currentUser.requireID()
                if let limit = maxTopicsPerUser, currentUser.role != .admin {
                    let count = try await topicClient.countForOwner(ownerID)
                    if count >= limit {
                        throw TopicError.quotaExceeded(limit: limit)
                    }
                }
                return try await topicClient.create(name, ownerID, publicRead, publicPublish)
            },
            updateTopic: { currentUser, name, publicRead, publicPublish in
                guard let topic = try await topicClient.getByName(name) else {
                    throw TopicError.notFound
                }
                let topicID = try topic.requireID()
                let ownerID = topic.$owner.id
                guard try currentUser.role == .admin || (currentUser.requireID()) == ownerID else {
                    throw TopicError.accessDenied
                }
                guard let updated = try await topicClient.update(topicID, publicRead, publicPublish) else {
                    throw TopicError.notFound
                }
                return updated
            },
            deleteTopic: { currentUser, name in
                guard let topic = try await topicClient.getByName(name) else {
                    throw TopicError.notFound
                }
                let topicID = try topic.requireID()
                let ownerID = topic.$owner.id
                guard try currentUser.role == .admin || (currentUser.requireID()) == ownerID else {
                    throw TopicError.accessDenied
                }
                try await topicClient.delete(topicID)
            }
        )
    }
}

struct TopicStats: Sendable {
    let subscriberCount: Int
    let messageCount: Int
    let lastMessageAt: Date?
    let deliveryStats: TopicDeliveryStats
}

struct TopicDeliveryStats: Sendable {
    let pending: Int
    let ongoing: Int
    let delivered: Int
    let failed: Int

    init(_ stats: DeliveryStats) {
        pending = stats.pending
        ongoing = stats.ongoing
        delivered = stats.delivered
        failed = stats.failed
    }
}
