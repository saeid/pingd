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
        _ topicName: String
    ) async throws -> [Message]

    let publishMessage: @Sendable (
        _ currentUser: User?,
        _ topicName: String,
        _ priority: UInt8,
        _ tags: [String]?,
        _ payload: MessagePayload,
        _ time: Date
    ) async throws -> Message
}

extension MessageFeature {
    static func live(
        topicClient: TopicClient,
        messageClient: MessageClient,
        dispatchFeature: DispatchFeature? = nil,
        topicBroadcaster: TopicBroadcaster? = nil
    ) -> Self {
        MessageFeature(
            listMessages: { currentUser, topicName in
                guard let topic = try await topicClient.getByName(topicName) else {
                    throw MessageError.topicNotFound
                }
                // open: anyone can read
                // protected + private: must be authenticated
                if topic.visibility != .open && currentUser == nil {
                    throw MessageError.accessDenied
                }
                let topicID = try topic.requireID()
                return try await messageClient.list(topicID)
            },
            publishMessage: { currentUser, topicName, priority, tags, payload, time in
                guard let topic = try await topicClient.getByName(topicName) else {
                    throw MessageError.topicNotFound
                }
                switch topic.visibility {
                case .open:
                    break
                case .protected:
                    guard currentUser != nil else { throw MessageError.accessDenied }
                case .private:
                    guard let user = currentUser else { throw MessageError.accessDenied }
                    let ownerID = topic.$owner.id
                    let userID = try user.requireID()
                    guard user.role == .admin || userID == ownerID else {
                        throw MessageError.accessDenied
                    }
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
