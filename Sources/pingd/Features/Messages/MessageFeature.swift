import Vapor

enum MessageError: AbortError {
    case topicNotFound
    case accessDenied

    var status: HTTPResponseStatus {
        switch self {
        case .topicNotFound: .notFound
        case .accessDenied: .forbidden
        }
    }

    var reason: String {
        switch self {
        case .topicNotFound: "Topic not found"
        case .accessDenied: "Access denied"
        }
    }
}

struct MessageFeature {
    let listMessages: @Sendable (
        _ currentUser: User?,
        _ topicName: String,
        _ topicPassword: String?
    ) async throws -> [Message]

    let publishMessage: @Sendable (
        _ currentUser: User?,
        _ topicName: String,
        _ topicPassword: String?,
        _ priority: UInt8,
        _ tags: [String]?,
        _ payload: MessagePayload,
        _ time: Date
    ) async throws -> Message
}

extension MessageFeature {
    static func live(
        topicClient: TopicClient,
        authClient: AuthClient,
        messageClient: MessageClient,
        dispatchFeature: DispatchFeature? = nil,
        topicBroadcaster: TopicBroadcaster? = nil
    ) -> Self {
        MessageFeature(
            listMessages: { currentUser, topicName, topicPassword in
                guard let topic = try await topicClient.getByName(topicName) else {
                    throw MessageError.topicNotFound
                }
                if try !TopicAccess.canRead(
                    topic: topic,
                    currentUser: currentUser,
                    topicPassword: topicPassword,
                    authClient: authClient
                ) {
                    throw MessageError.accessDenied
                }
                let topicID = try topic.requireID()
                return try await messageClient.list(topicID)
            },
            publishMessage: { currentUser, topicName, topicPassword, priority, tags, payload, time in
                guard let topic = try await topicClient.getByName(topicName) else {
                    throw MessageError.topicNotFound
                }
                if try !TopicAccess.canPublish(
                    topic: topic,
                    currentUser: currentUser,
                    topicPassword: topicPassword,
                    authClient: authClient
                ) {
                    throw MessageError.accessDenied
                }
                let topicID = try topic.requireID()
                let message = try await messageClient.publish(topicID, priority, tags, payload, time)

                // fan-out: create deliveries for subscribed devices
                if let dispatchFeature {
                    let messageID = try message.requireID()
                    try await dispatchFeature.fanOut(messageID, topicID)
                }

                // broadcast to SSE listeners
                if let topicBroadcaster {
                    await topicBroadcaster.broadcast(topic: topicName, payload: payload)
                }

                return message
            }
        )
    }
}
