import Foundation

/// In-memory pub/sub for SSE. Holds active listeners per topic.
/// When a message is published, all listeners for that topic get notified.
/// Each listener is an AsyncStream continuation — writing to it pushes data to the SSE connection.
actor TopicBroadcaster {
    private var listeners: [String: [UUID: AsyncStream<MessagePayload>.Continuation]] = [:]

    func subscribe(topic: String) -> (id: UUID, stream: AsyncStream<MessagePayload>) {
        let id = UUID()
        let (stream, continuation) = AsyncStream<MessagePayload>.makeStream()
        listeners[topic, default: [:]][id] = continuation
        return (id, stream)
    }

    func unsubscribe(topic: String, id: UUID) {
        listeners[topic]?[id]?.finish()
        listeners[topic]?.removeValue(forKey: id)
        if listeners[topic]?.isEmpty == true {
            listeners.removeValue(forKey: topic)
        }
    }

    func broadcast(topic: String, payload: MessagePayload) {
        guard let topicListeners = listeners[topic] else { return }
        for (_, continuation) in topicListeners {
            continuation.yield(payload)
        }
    }
}
