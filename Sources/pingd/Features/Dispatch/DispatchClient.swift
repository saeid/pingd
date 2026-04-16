import Fluent
import Vapor
import Foundation

struct DispatchClient {
    let createDelivery: @Sendable (_ messageID: UUID, _ deviceID: UUID) async throws -> MessageDelivery
    let listForMessage: @Sendable (_ messageID: UUID) async throws -> [MessageDelivery]
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
            fetchPending: { limit in
                try await MessageDelivery.query(on: app.db)
                    .filter(\.$status == .pending)
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
            MessageDelivery(messageId: messageID, deviceId: deviceID, status: .pending, retryCount: 0)
        },
        listForMessage: @escaping @Sendable (UUID) async throws -> [MessageDelivery] = { _ in [] },
        fetchPending: @escaping @Sendable (Int) async throws -> [MessageDelivery] = { _ in [] },
        updateStatus: @escaping @Sendable (UUID, DeliveryStatus, UInt8) async throws -> Void = { _, _, _ in }
    ) -> Self {
        DispatchClient(createDelivery: createDelivery, listForMessage: listForMessage, fetchPending: fetchPending, updateStatus: updateStatus)
    }
}
