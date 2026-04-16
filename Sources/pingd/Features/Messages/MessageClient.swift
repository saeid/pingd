import Fluent
import Vapor
import Foundation

struct MessageClient {
    let get: @Sendable (UUID) async throws -> Message?
    let list: @Sendable (_ topicID: UUID) async throws -> [Message]
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
                try await Message.find(id, on: app.db)
            },
            list: { topicID in
                try await Message.query(on: app.db)
                    .filter(\.$topic.$id == topicID)
                    .sort(\.$time, .descending)
                    .all()
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
        publish: @escaping @Sendable (UUID, UInt8, [String]?, MessagePayload, Date) async throws -> Message = { topicID, priority, _, payload, time in
            Message(topicID: topicID, time: time, priority: priority, payload: payload)
        }
    ) -> Self {
        MessageClient(get: get, list: list, publish: publish)
    }
}
