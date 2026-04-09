import Fluent
import Foundation

enum DeliveryStatus: String, CaseIterable, Codable {
    case pending
    case ongoing
    case delivered
    case failed
}

final class MessageDelivery: Model, @unchecked Sendable {
    static let schema = "messages_delivery"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "message_id")
    var message: Message

    @Parent(key: "device_id")
    var device: Device

    @Enum(key: "status")
    var status: DeliveryStatus

    @Field(key: "retry_count")
    var retryCount: UInt8

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        messageId: UUID,
        deviceId: UUID,
        status: DeliveryStatus,
        retryCount: UInt8
    ) {
        self.id = id
        $message.id = messageId
        $device.id = deviceId
        self.status = status
        self.retryCount = retryCount
    }
}
