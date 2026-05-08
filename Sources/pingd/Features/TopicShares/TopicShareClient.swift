import Crypto
import Fluent
import Foundation
import Vapor

struct TopicShareClient {
    let listForTopic: @Sendable (_ topicID: UUID) async throws -> [TopicShareToken]
    let get: @Sendable (UUID) async throws -> TopicShareToken?
    let getByTokenHash: @Sendable (String) async throws -> TopicShareToken?
    let create: @Sendable (
        _ topicID: UUID,
        _ tokenHash: String,
        _ label: String?,
        _ accessLevel: AccessLevel,
        _ createdByUserID: UUID,
        _ expiresAt: Date?
    ) async throws -> TopicShareToken
    let updateTokenHash: @Sendable (UUID, String) async throws -> TopicShareToken?
    let update: @Sendable (
        _ id: UUID,
        _ label: String??,
        _ accessLevel: AccessLevel?,
        _ expiresAt: Date??
    ) async throws -> TopicShareToken?
    let delete: @Sendable (UUID) async throws -> Void
}

extension TopicShareClient {
    static func live(app: Application) -> Self {
        TopicShareClient(
            listForTopic: { topicID in
                try await TopicShareToken.query(on: app.db)
                    .filter(\.$topic.$id == topicID)
                    .all()
            },
            get: { id in
                try await TopicShareToken.find(id, on: app.db)
            },
            getByTokenHash: { hash in
                try await TopicShareToken.query(on: app.db)
                    .filter(\.$tokenHash == hash)
                    .first()
            },
            create: { topicID, tokenHash, label, accessLevel, createdByUserID, expiresAt in
                let share = TopicShareToken(
                    topicID: topicID,
                    tokenHash: tokenHash,
                    label: label,
                    accessLevel: accessLevel,
                    createdByUserID: createdByUserID,
                    expiresAt: expiresAt
                )
                try await share.save(on: app.db)
                return share
            },
            updateTokenHash: { id, hash in
                guard let share = try await TopicShareToken.find(id, on: app.db) else { return nil }
                share.tokenHash = hash
                try await share.save(on: app.db)
                return share
            },
            update: { id, label, accessLevel, expiresAt in
                guard let share = try await TopicShareToken.find(id, on: app.db) else { return nil }
                if let label { share.label = label }
                if let accessLevel { share.accessLevel = accessLevel }
                if let expiresAt { share.expiresAt = expiresAt }
                try await share.save(on: app.db)
                return share
            },
            delete: { id in
                guard let share = try await TopicShareToken.find(id, on: app.db) else { return }
                try await share.delete(on: app.db)
            }
        )
    }

    static func mock(
        listForTopic: @escaping @Sendable (UUID) async throws -> [TopicShareToken] = { _ in [] },
        get: @escaping @Sendable (UUID) async throws -> TopicShareToken? = { _ in nil },
        getByTokenHash: @escaping @Sendable (String) async throws -> TopicShareToken? = { _ in nil },
        create: @escaping @Sendable (UUID, String, String?, AccessLevel, UUID, Date?) async throws -> TopicShareToken = { topicID, hash, label, level, createdBy, expiresAt in
            TopicShareToken(topicID: topicID, tokenHash: hash, label: label, accessLevel: level, createdByUserID: createdBy, expiresAt: expiresAt)
        },
        updateTokenHash: @escaping @Sendable (UUID, String) async throws -> TopicShareToken? = { _, _ in nil },
        update: @escaping @Sendable (UUID, String??, AccessLevel?, Date??) async throws -> TopicShareToken? = { _, _, _, _ in nil },
        delete: @escaping @Sendable (UUID) async throws -> Void = { _ in }
    ) -> Self {
        TopicShareClient(
            listForTopic: listForTopic,
            get: get,
            getByTokenHash: getByTokenHash,
            create: create,
            updateTokenHash: updateTokenHash,
            update: update,
            delete: delete
        )
    }
}

enum TopicShareTokenCodec {
    static let prefix = "tk_"

    static func generate() -> (raw: String, hash: String) {
        var bytes = [UInt8](repeating: 0, count: 32)
        for index in 0..<bytes.count {
            bytes[index] = UInt8.random(in: 0...UInt8.max)
        }
        let randomPart = bytes.map { String(format: "%02x", $0) }.joined()
        let raw = prefix + randomPart
        return (raw, hash(raw))
    }

    static func hash(_ raw: String) -> String {
        let data = Data(raw.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func isWellFormed(_ raw: String) -> Bool {
        raw.hasPrefix(prefix) && raw.count > prefix.count
    }
}
