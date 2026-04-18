import Foundation

struct TopicDTO: Codable {
    let id: UUID
    let name: String
    let visibility: String
    let ownerUserID: UUID
    let createdAt: Date?
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
    let label: String?
    let tokenHash: String
    let expiresAt: Date?
    let createdAt: Date?
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

struct DeliveryDTO: Codable {
    let id: UUID
    let messageID: UUID
    let deviceID: UUID
    let status: String
    let retryCount: UInt8
    let createdAt: Date?
    let updatedAt: Date?
}
