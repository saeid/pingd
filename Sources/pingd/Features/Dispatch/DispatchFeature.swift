import Vapor

struct DispatchFeature {
    let fanOut: @Sendable (_ messageID: UUID, _ topicID: UUID) async throws -> Void
    let listDeliveries: @Sendable (_ messageID: UUID) async throws -> [MessageDelivery]
}

extension DispatchFeature {
    static func live(
        dispatchClient: DispatchClient,
        subscriptionClient: SubscriptionClient,
        deviceClient: DeviceClient
    ) -> Self {
        DispatchFeature(
            fanOut: { messageID, topicID in
                let subscriptions = try await subscriptionClient.listForTopic(topicID)
                for sub in subscriptions {
                    let deviceID = sub.$device.id
                    if let device = try await deviceClient.get(deviceID),
                       device.isActive,
                       device.deliveryEnabled {
                        _ = try await dispatchClient.createDelivery(messageID, deviceID)
                    }
                }
            },
            listDeliveries: { messageID in
                try await dispatchClient.listForMessage(messageID)
            }
        )
    }
}
