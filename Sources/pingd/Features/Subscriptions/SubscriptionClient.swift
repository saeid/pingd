import Fluent
import Vapor
import Foundation

struct SubscriptionClient {
    let list: @Sendable (_ deviceID: UUID) async throws -> [DeviceSubscription]
    let listForUser: @Sendable (_ userID: UUID) async throws -> [DeviceSubscription]
    let listForTopic: @Sendable (_ topicID: UUID) async throws -> [DeviceSubscription]
    let countForTopic: @Sendable (_ topicID: UUID) async throws -> Int
    let create: @Sendable (_ deviceID: UUID, _ topicID: UUID) async throws -> DeviceSubscription
    let delete: @Sendable (_ deviceID: UUID, _ topicID: UUID) async throws -> Void
}

extension SubscriptionClient {
    static func live(app: Application) -> Self {
        SubscriptionClient(
            list: { deviceID in
                try await DeviceSubscription.query(on: app.db)
                    .filter(\.$device.$id == deviceID)
                    .with(\.$topic)
                    .all()
            },
            listForUser: { userID in
                try await DeviceSubscription.query(on: app.db)
                    .join(Device.self, on: \DeviceSubscription.$device.$id == \Device.$id)
                    .join(Topic.self, on: \DeviceSubscription.$topic.$id == \Topic.$id)
                    .filter(Device.self, \.$user.$id == userID)
                    .all()
            },
            listForTopic: { topicID in
                try await DeviceSubscription.query(on: app.db)
                    .filter(\.$topic.$id == topicID)
                    .all()
            },
            countForTopic: { topicID in
                try await DeviceSubscription.query(on: app.db)
                    .filter(\.$topic.$id == topicID)
                    .count()
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
        listForUser: @escaping @Sendable (UUID) async throws -> [DeviceSubscription] = { _ in [] },
        listForTopic: @escaping @Sendable (UUID) async throws -> [DeviceSubscription] = { _ in [] },
        countForTopic: @escaping @Sendable (UUID) async throws -> Int = { _ in 0 },
        create: @escaping @Sendable (UUID, UUID) async throws -> DeviceSubscription = { deviceID, topicID in
            DeviceSubscription(deviceId: deviceID, topicId: topicID)
        },
        delete: @escaping @Sendable (UUID, UUID) async throws -> Void = { _, _ in }
    ) -> Self {
        SubscriptionClient(
            list: list,
            listForUser: listForUser,
            listForTopic: listForTopic,
            countForTopic: countForTopic,
            create: create,
            delete: delete
        )
    }
}
