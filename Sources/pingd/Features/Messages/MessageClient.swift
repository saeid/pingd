import Fluent
import Vapor
import Foundation

struct MessageClient {
    let get: @Sendable (UUID) async throws -> Message?
    let list: @Sendable (_ topicID: UUID) async throws -> [Message]
    let count: @Sendable (_ topicID: UUID) async throws -> Int
    let lastMessage: @Sendable (_ topicID: UUID) async throws -> Message?
    let publish: @Sendable (
        _ topicID: UUID,
        _ priority: UInt8,
        _ tags: [String]?,
        _ payload: MessagePayload,
        _ time: Date
    ) async throws -> Message
}

extension MessageClient {
    static func live(app: Application) -> Self {
        MessageClient(
            get: { id in
                try await Message.query(on: app.db)
                    .filter(\.$id == id)
                    .with(\.$topic)
                    .first()
            },
            list: { topicID in
                try await Message.query(on: app.db)
                    .filter(\.$topic.$id == topicID)
                    .sort(\.$time, .descending)
                    .all()
            },
            count: { topicID in
                try await Message.query(on: app.db)
                    .filter(\.$topic.$id == topicID)
                    .count()
            },
            lastMessage: { topicID in
                try await Message.query(on: app.db)
                    .filter(\.$topic.$id == topicID)
                    .sort(\.$time, .descending)
                    .first()
            },
            publish: { topicID, priority, tags, payload, time in
                let message = Message(
                    topicID: topicID,
                    time: time,
                    priority: priority,
                    tags: tags,
                    payload: payload
                )
                try await message.save(on: app.db)
                return message
            }
        )
    }

    static func mock(
        get: @escaping @Sendable (UUID) async throws -> Message? = { _ in nil },
        list: @escaping @Sendable (UUID) async throws -> [Message] = { _ in [] },
        count: @escaping @Sendable (UUID) async throws -> Int = { _ in 0 },
        lastMessage: @escaping @Sendable (UUID) async throws -> Message? = { _ in nil },
        publish: @escaping @Sendable (UUID, UInt8, [String]?, MessagePayload, Date) async throws -> Message = { topicID, priority, _, payload, time in
            Message(topicID: topicID, time: time, priority: priority, payload: payload)
        }
    ) -> Self {
        MessageClient(
            get: get,
            list: list,
            count: count,
            lastMessage: lastMessage,
            publish: publish
        )
    }
}
