import Vapor

enum SubscriptionError: AbortError {
    case deviceNotFound
    case topicNotFound
    case accessDenied
    case alreadySubscribed

    var status: HTTPResponseStatus {
        switch self {
        case .deviceNotFound, .topicNotFound: .notFound
        case .accessDenied: .forbidden
        case .alreadySubscribed: .conflict
        }
    }

    var reason: String {
        switch self {
        case .deviceNotFound: "Device not found"
        case .topicNotFound: "Topic not found"
        case .accessDenied: "Access denied"
        case .alreadySubscribed: "Already subscribed to this topic"
        }
    }
}

struct SubscriptionFeature {
    let listSubscriptions: @Sendable (
        _ currentUser: User,
        _ deviceID: UUID
    ) async throws -> [DeviceSubscription]

    let listForUser: @Sendable (
        _ currentUser: User,
        _ username: String
    ) async throws -> [UserSubscriptionResponse]

    let subscribe: @Sendable (
        _ currentUser: User,
        _ deviceID: UUID,
        _ topicName: String,
        _ topicPassword: String?
    ) async throws -> (DeviceSubscription, Topic)

    let unsubscribe: @Sendable (
        _ currentUser: User,
        _ deviceID: UUID,
        _ topicName: String
    ) async throws -> Void
}

extension SubscriptionFeature {
    static func live(
        subscriptionClient: SubscriptionClient,
        deviceClient: DeviceClient,
        topicClient: TopicClient,
        userClient: UserClient,
        authClient: AuthClient,
        permissionClient: PermissionClient
    ) -> Self {
        SubscriptionFeature(
            listSubscriptions: { currentUser, deviceID in
                guard let device = try await deviceClient.get(deviceID) else {
                    throw SubscriptionError.deviceNotFound
                }
                let ownerID = device.$user.id
                let currentUserID = try currentUser.requireID()
                guard currentUser.role == .admin || currentUserID == ownerID else {
                    throw SubscriptionError.accessDenied
                }
                return try await subscriptionClient.list(deviceID)
            },
            listForUser: { currentUser, username in
                try userClient.checkUserPermission(for: currentUser, targetUser: username)
                let userID = try await userClient.getUserId(for: username)
                let subscriptions = try await subscriptionClient.listForUser(userID)
                return try subscriptions.map { subscription in
                    let device = try subscription.joined(Device.self)
                    let topic = try subscription.joined(Topic.self)
                    return UserSubscriptionResponse(
                        id: try subscription.requireID(),
                        device: .init(
                            id: device.id!,
                            name: device.name,
                            platform: device.platform.rawValue
                        ),
                        topic: .init(
                            id: topic.id!,
                            name: topic.name,
                            visibility: topic.visibility.rawValue,
                            hasPassword: topic.passwordHash != nil,
                            ownerUserID: topic.$owner.id
                        ),
                        createdAt: subscription.createdAt
                    )
                }
            },
            subscribe: { currentUser, deviceID, topicName, topicPassword in
                guard let device = try await deviceClient.get(deviceID) else {
                    throw SubscriptionError.deviceNotFound
                }
                let ownerID = device.$user.id
                let currentUserID = try currentUser.requireID()
                guard currentUser.role == .admin || currentUserID == ownerID else {
                    throw SubscriptionError.accessDenied
                }
                guard let topic = try await topicClient.getByName(topicName) else {
                    throw SubscriptionError.topicNotFound
                }
                if try await !TopicAccess.canRead(
                    topic: topic,
                    currentUser: currentUser,
                    topicPassword: topicPassword,
                    authClient: authClient,
                    permissionClient: permissionClient
                ) {
                    throw SubscriptionError.accessDenied
                }
                let topicID = try topic.requireID()
                do {
                    let subscription = try await subscriptionClient.create(deviceID, topicID)
                    return (subscription, topic)
                } catch {
                    throw SubscriptionError.alreadySubscribed
                }
            },
            unsubscribe: { currentUser, deviceID, topicName in
                guard let device = try await deviceClient.get(deviceID) else {
                    throw SubscriptionError.deviceNotFound
                }
                let ownerID = device.$user.id
                let currentUserID = try currentUser.requireID()
                guard currentUser.role == .admin || currentUserID == ownerID else {
                    throw SubscriptionError.accessDenied
                }
                guard let topic = try await topicClient.getByName(topicName) else {
                    throw SubscriptionError.topicNotFound
                }
                let topicID = try topic.requireID()
                try await subscriptionClient.delete(deviceID, topicID)
            }
        )
    }
}
