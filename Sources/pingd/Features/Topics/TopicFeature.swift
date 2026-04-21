import Vapor

enum TopicError: AbortError {
    case notFound
    case nameTaken
    case accessDenied

    var status: HTTPResponseStatus {
        switch self {
        case .notFound: .notFound
        case .nameTaken: .badRequest
        case .accessDenied: .forbidden
        }
    }

    var reason: String {
        switch self {
        case .notFound: "Topic not found"
        case .nameTaken: "Topic name already taken"
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
        _ topicPassword: String?
    ) async throws -> Topic

    let createTopic: @Sendable (
        _ currentUser: User,
        _ name: String,
        _ visibility: TopicVisibility,
        _ passwordHash: String?
    ) async throws -> Topic

    let updateTopic: @Sendable (
        _ currentUser: User,
        _ name: String,
        _ visibility: TopicVisibility?,
        _ passwordHash: String??
    ) async throws -> Topic

    let deleteTopic: @Sendable (
        _ currentUser: User,
        _ name: String
    ) async throws -> Void
}

extension TopicFeature {
    static func live(
        topicClient: TopicClient,
        authClient: AuthClient,
        permissionClient: PermissionClient,
        messageClient: MessageClient,
        subscriptionClient: SubscriptionClient,
        dispatchClient: DispatchClient
    ) -> Self {
        TopicFeature(
            listTopics: { currentUser in
                let all = try await topicClient.list()

                guard let user = currentUser else {
                    return all.filter { $0.visibility == .open }
                }
                if user.role == .admin { return all }

                let userID = try user.requireID()
                let userPermissions = try await permissionClient.listForUser(userID)
                let globalPermissions = try await permissionClient.listGlobal()
                let allPermissions = userPermissions + globalPermissions

                return all.filter { topic in
                    let resolved = PermissionResolver.resolve(permissions: allPermissions, topicName: topic.name)
                    if let resolved {
                        return resolved != .deny && resolved != .writeOnly
                    }
                    switch topic.visibility {
                    case .open, .protected: return true
                    case .private: return topic.$owner.id == userID
                    }
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
            getTopic: { currentUser, name, topicPassword in
                guard let topic = try await topicClient.getByName(name) else {
                    throw TopicError.notFound
                }
                if try await !TopicAccess.canRead(
                    topic: topic,
                    currentUser: currentUser,
                    topicPassword: topicPassword,
                    authClient: authClient,
                    permissionClient: permissionClient
                ) {
                    throw TopicError.accessDenied
                }
                return topic
            },
            createTopic: { currentUser, name, visibility, passwordHash in
                if try await topicClient.getByName(name) != nil {
                    throw TopicError.nameTaken
                }
                let ownerID = try currentUser.requireID()
                return try await topicClient.create(name, ownerID, visibility, passwordHash)
            },
            updateTopic: { currentUser, name, visibility, passwordHash in
                guard let topic = try await topicClient.getByName(name) else {
                    throw TopicError.notFound
                }
                let topicID = try topic.requireID()
                let ownerID = topic.$owner.id
                guard try currentUser.role == .admin || (currentUser.requireID()) == ownerID else {
                    throw TopicError.accessDenied
                }
                guard let updated = try await topicClient.update(topicID, visibility, passwordHash) else {
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
