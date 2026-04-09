import Fluent
import Foundation

final class DeviceSubscription: Model, @unchecked Sendable {
    static let schema = "device_subscriptions"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "device_id")
    var device: Device

    @Parent(key: "topic_id")
    var topic: Topic

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        deviceId: UUID,
        topicId: UUID
    ) {
        self.id = id
        $device.id = deviceId
        $topic.id = topicId
    }
}
