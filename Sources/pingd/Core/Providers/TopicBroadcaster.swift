import Foundation
import Vapor

/// In-memory pub/sub for SSE. Holds active listeners per topic.
/// When a message is published, all listeners for that topic get notified.
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

    func shutdown() {
        for (_, topicListeners) in listeners {
            for (_, continuation) in topicListeners {
                continuation.finish()
            }
        }
        listeners.removeAll()
    }
}

struct TopicBroadcasterLifecycleHandler: LifecycleHandler {
    let broadcaster: TopicBroadcaster

    func shutdownAsync(_ application: Application) async {
        await broadcaster.shutdown()
        application.logger.info("SSE broadcaster stopped")
    }
}
