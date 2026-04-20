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

    let subscribe: @Sendable (
        _ currentUser: User,
        _ deviceID: UUID,
        _ topicName: String
    ) async throws -> DeviceSubscription

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
            subscribe: { currentUser, deviceID, topicName in
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
                    topicPassword: nil,
                    authClient: authClient,
                    permissionClient: permissionClient
                ) {
                    throw SubscriptionError.accessDenied
                }
                let topicID = try topic.requireID()
                do {
                    return try await subscriptionClient.create(deviceID, topicID)
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
