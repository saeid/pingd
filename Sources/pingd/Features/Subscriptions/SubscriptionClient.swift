import Fluent
import Vapor
import Foundation

struct SubscriptionClient {
    let list: @Sendable (_ deviceID: UUID) async throws -> [DeviceSubscription]
    let listForTopic: @Sendable (_ topicID: UUID) async throws -> [DeviceSubscription]
    let create: @Sendable (_ deviceID: UUID, _ topicID: UUID) async throws -> DeviceSubscription
    let delete: @Sendable (_ deviceID: UUID, _ topicID: UUID) async throws -> Void
}

extension SubscriptionClient {
    static func live(app: Application) -> Self {
        SubscriptionClient(
            list: { deviceID in
                try await DeviceSubscription.query(on: app.db)
                    .filter(\.$device.$id == deviceID)
                    .all()
            },
            listForTopic: { topicID in
                try await DeviceSubscription.query(on: app.db)
                    .filter(\.$topic.$id == topicID)
                    .all()
            },
            create: { deviceID, topicID in
                let subscription = DeviceSubscription(deviceId: deviceID, topicId: topicID)
                try await subscription.save(on: app.db)
                return subscription
            },
            delete: { deviceID, topicID in
                try await DeviceSubscription.query(on: app.db)
                    .filter(\.$device.$id == deviceID)
                    .filter(\.$topic.$id == topicID)
                    .delete()
            }
        )
    }

    static func mock(
        list: @escaping @Sendable (UUID) async throws -> [DeviceSubscription] = { _ in [] },
        listForTopic: @escaping @Sendable (UUID) async throws -> [DeviceSubscription] = { _ in [] },
        create: @escaping @Sendable (UUID, UUID) async throws -> DeviceSubscription = { deviceID, topicID in
            DeviceSubscription(deviceId: deviceID, topicId: topicID)
        },
        delete: @escaping @Sendable (UUID, UUID) async throws -> Void = { _, _ in }
    ) -> Self {
        SubscriptionClient(list: list, listForTopic: listForTopic, create: create, delete: delete)
    }
}
