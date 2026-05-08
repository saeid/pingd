import Foundation
import Vapor

enum MessageError: AbortError {
    case topicNotFound
    case accessDenied
    case invalidPayload(String)

    var status: HTTPResponseStatus {
        switch self {
        case .topicNotFound: .notFound
        case .accessDenied: .forbidden
        case .invalidPayload: .badRequest
        }
    }

    var reason: String {
        switch self {
        case .topicNotFound: "Topic not found"
        case .accessDenied: "Access denied"
        case let .invalidPayload(message): message
        }
    }
}

struct MessageFeature {
    let listMessages: @Sendable (
        _ currentUser: User?,
        _ topicName: String,
        _ topicToken: String?,
        _ now: Date
    ) async throws -> [Message]

    let publishMessage: @Sendable (
        _ currentUser: User?,
        _ topicName: String,
        _ topicToken: String?,
        _ priority: UInt8,
        _ tags: [String]?,
        _ payload: MessagePayload,
        _ time: Date,
        _ ttl: Int?
    ) async throws -> Message
}

extension MessageFeature {
    static func live(
        topicClient: TopicClient,
        topicShareClient: TopicShareClient,
        permissionClient: PermissionClient,
        messageClient: MessageClient,
        dispatchFeature: DispatchFeature? = nil,
        topicBroadcaster: TopicBroadcaster? = nil
    ) -> Self {
        MessageFeature(
            listMessages: { currentUser, topicName, topicToken, now in
                guard let topic = try await topicClient.getByName(topicName) else {
                    throw MessageError.topicNotFound
                }
                if try await !TopicAccess.canRead(
                    topic: topic,
                    currentUser: currentUser,
                    topicToken: topicToken,
                    topicShareClient: topicShareClient,
                    permissionClient: permissionClient,
                    now: now
                ) {
                    throw MessageError.accessDenied
                }
                let topicID = try topic.requireID()
                return try await messageClient.list(topicID, now)
            },
            publishMessage: { currentUser, topicName, topicToken, priority, tags, payload, time, ttl in
                guard (1...3).contains(priority) else {
                    throw MessageError.invalidPayload("priority must be between 1 and 3")
                }
                guard let topic = try await topicClient.getByName(topicName) else {
                    throw MessageError.topicNotFound
                }
                if try await !TopicAccess.canPublish(
                    topic: topic,
                    currentUser: currentUser,
                    topicToken: topicToken,
                    topicShareClient: topicShareClient,
                    permissionClient: permissionClient,
                    now: time
                ) {
                    throw MessageError.accessDenied
                }
                let topicID = try topic.requireID()
                let expiresAt = ttl.map { time.addingTimeInterval(TimeInterval($0)) }
                let message = try await messageClient.publish(topicID, priority, tags, payload, time, expiresAt)

                if let dispatchFeature {
                    let messageID = try message.requireID()
                    try await dispatchFeature.fanOut(messageID, topicID)
                }

                if let topicBroadcaster {
                    let broadcast = BroadcastMessage(
                        priority: priority,
                        tags: tags,
                        payload: payload,
                        time: time
                    )
                    await topicBroadcaster.broadcast(topic: topicName, message: broadcast)
                }

                return message
            }
        )
    }
}
