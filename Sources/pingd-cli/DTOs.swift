import Foundation

struct TopicDTO: Codable {
    let id: UUID
    let name: String
    let visibility: String
    let ownerUserID: UUID
    let createdAt: Date?
}

struct TopicStatsDTO: Codable {
    let subscriberCount: Int
    let messageCount: Int
    let lastMessageAt: Date?
    let deliveryStats: TopicDeliveryStatsDTO
}

struct TopicDeliveryStatsDTO: Codable {
    let pending: Int
    let ongoing: Int
    let delivered: Int
    let failed: Int
}

struct MessageDTO: Codable {
    let id: UUID
    let topicID: UUID
    let time: Date
    let priority: UInt8
    let tags: [String]?
    let payload: PayloadDTO
    let createdAt: Date?
}

struct PayloadDTO: Codable {
    let title: String?
    let subtitle: String?
    let body: String
}

struct UserDTO: Codable {
    let id: UUID
    let username: String
    let role: String
    let createdAt: Date?
}

struct TokenDTO: Codable {
    let id: UUID
    let token: String
    let label: String?
    let expiresAt: Date?
    let createdAt: Date?
    let lastUsedAt: Date?
}

struct BroadcastDTO: Codable {
    let priority: UInt8
    let tags: [String]?
    let payload: PayloadDTO
    let time: Date
}

struct PublishRequest: Codable {
    let priority: UInt8
    let tags: [String]?
    let payload: PayloadDTO
}

struct PermissionDTO: Codable {
    let id: UUID
    let userID: UUID?
    let scope: String
    let accessLevel: String
    let topicPattern: String
    let createdAt: Date?
}

struct CreatePermissionDTO: Codable {
    let accessLevel: String
    let topicPattern: String
}

struct UserSubscriptionDTO: Codable {
    let id: UUID
    let device: DeviceInfo
    let topic: TopicInfo
    let createdAt: Date?

    struct DeviceInfo: Codable {
        let id: UUID
        let name: String
        let platform: String
    }

    struct TopicInfo: Codable {
        let id: UUID
        let name: String
        let visibility: String
        let hasPassword: Bool
        let ownerUserID: UUID
    }
}

struct WebhookTemplateDTO: Codable {
    var title: String?
    var subtitle: String?
    var body: String?
    var tags: String?
    var priority: UInt8?
    var ttl: Int?
}

struct WebhookDTO: Codable {
    let id: UUID
    let topicID: UUID
    let template: WebhookTemplateDTO
    let createdAt: Date?
}

struct CreateWebhookResponseDTO: Codable {
    let id: UUID
    let topicID: UUID
    let token: String
    let template: WebhookTemplateDTO
    let createdAt: Date?
}

struct WebhookTemplateRequestDTO: Codable {
    let template: WebhookTemplateDTO
}

struct DeliveryDTO: Codable {
    let id: UUID
    let messageID: UUID
    let deviceID: UUID
    let status: String
    let retryCount: UInt8
    let createdAt: Date?
    let updatedAt: Date?
}
