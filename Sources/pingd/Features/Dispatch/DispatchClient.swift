import Fluent
import Foundation
import Vapor

struct DeliveryStats {
    let pending: Int
    let ongoing: Int
    let delivered: Int
    let failed: Int
}

struct DispatchClient {
    let createDelivery: @Sendable (_ messageID: UUID, _ deviceID: UUID) async throws -> MessageDelivery
    let listForMessage: @Sendable (_ messageID: UUID) async throws -> [MessageDelivery]
    let statsForTopic: @Sendable (_ topicID: UUID) async throws -> DeliveryStats
    let fetchPending: @Sendable (_ limit: Int) async throws -> [MessageDelivery]
    let updateStatus: @Sendable (_ deliveryID: UUID, _ status: DeliveryStatus, _ retryCount: UInt8) async throws -> Void
}

extension DispatchClient {
    static func live(app: Application) -> Self {
        DispatchClient(
            createDelivery: { messageID, deviceID in
                let delivery = MessageDelivery(
                    messageId: messageID,
                    deviceId: deviceID,
                    status: .pending,
                    retryCount: 0
                )
                try await delivery.save(on: app.db)
                return delivery
            },
            listForMessage: { messageID in
                try await MessageDelivery.query(on: app.db)
                    .filter(\.$message.$id == messageID)
                    .all()
            },
            statsForTopic: { topicID in
                func count(status: DeliveryStatus) async throws -> Int {
                    try await MessageDelivery.query(on: app.db)
                        .join(Message.self, on: \MessageDelivery.$message.$id == \Message.$id)
                        .filter(Message.self, \.$topic.$id == topicID)
                        .filter(\.$status == status)
                        .count()
                }

                return try await DeliveryStats(
                    pending: count(status: .pending),
                    ongoing: count(status: .ongoing),
                    delivered: count(status: .delivered),
                    failed: count(status: .failed)
                )
            },
            fetchPending: { limit in
                try await MessageDelivery.query(on: app.db)
                    .filter(\.$status == .pending)
                    .sort(\.$createdAt, .ascending)
                    .limit(limit)
                    .all()
            },
            updateStatus: { deliveryID, status, retryCount in
                guard let delivery = try await MessageDelivery.find(deliveryID, on: app.db) else { return }
                delivery.status = status
                delivery.retryCount = retryCount
                try await delivery.save(on: app.db)
            }
        )
    }

    static func mock(
        createDelivery: @escaping @Sendable (UUID, UUID) async throws -> MessageDelivery = { messageID, deviceID in
            MessageDelivery(
                messageId: messageID,
                deviceId: deviceID,
                status: .pending,
                retryCount: 0
            )
        },
        listForMessage: @escaping @Sendable (UUID) async throws -> [MessageDelivery] = { _ in [] },
        statsForTopic: @escaping @Sendable (UUID) async throws -> DeliveryStats = { _ in
            DeliveryStats(pending: 0, ongoing: 0, delivered: 0, failed: 0)
        },
        fetchPending: @escaping @Sendable (Int) async throws -> [MessageDelivery] = { _ in [] },
        updateStatus: @escaping @Sendable (UUID, DeliveryStatus, UInt8) async throws -> Void = { _, _, _ in }
    ) -> Self {
        DispatchClient(
            createDelivery: createDelivery,
            listForMessage: listForMessage,
            statsForTopic: statsForTopic,
            fetchPending: fetchPending,
            updateStatus: updateStatus
        )
    }
}
