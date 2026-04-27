import Foundation
import Vapor
import Fluent

struct TokenClient {
    let createToken: @Sendable (UUID, String?, Date?) async throws -> Token
    let get: @Sendable (UUID) async throws -> Token?
    let findByLabel: @Sendable (_ userID: UUID, _ label: String, _ now: Date) async throws -> Token?
    let listUserTokens: @Sendable (_ userID: UUID, _ now: Date) async throws -> [Token]
    let revokeToken: @Sendable (UUID) async throws -> Void
    let revokeByHash: @Sendable (String) async throws -> Void
    let markTokenUse: @Sendable (String, String, Date) async throws -> User
}

extension TokenClient {
    static func live(app: Application) -> Self {
        TokenClient(
            createToken: { userId, label, expiresAt in
                let token = Token(
                    userID: userId,
                    tokenHash: generateToken(),
                    label: label,
                    expiresAt: expiresAt
                )
                try await token.save(on: app.db)
                return token
            },
            get: { id in
                try await Token.find(id, on: app.db)
            },
            findByLabel: { userId, label, now in
                try await Token.query(on: app.db)
                    .filter(\.$user.$id == userId)
                    .filter(\.$label == label)
                    .group(.or) { group in
                        group.filter(\.$expiresAt == nil)
                        group.filter(\.$expiresAt > now)
                    }
                    .first()
            },
            listUserTokens: { userId, now in
                try await Token.query(on: app.db)
                    .filter(\.$user.$id == userId)
                    .group(.or) { group in
                        group.filter(\.$expiresAt == nil)
                        group.filter(\.$expiresAt > now)
                    }
                    .all()
            },
            revokeToken: { tokenId in
                guard let token = try await Token.find(tokenId, on: app.db) else {
                    return
                }
                try await token.delete(on: app.db)
            },
            revokeByHash: { tokenHash in
                guard let token = try await Token.query(on: app.db)
                    .filter(\.$tokenHash == tokenHash)
                    .first()
                else { return }
                try await token.delete(on: app.db)
            },
            markTokenUse: { tokenHash, ip, now in
                guard let token = try await Token.query(on: app.db)
                    .filter(\.$tokenHash == tokenHash)
                    .with(\.$user)
                    .first()
                else {
                    throw AuthError.invalidCredentials
                }
                guard token.expiresAt == nil || token.expiresAt! > now else {
                    throw AuthError.invalidCredentials
                }
                token.lastUsedAt = now
                token.lastUsedIp = ip
                try await token.save(on: app.db)
                return token.user
            }
        )
    }

    static func mock() -> Self {
        TokenClient(
            createToken: { _, _, _ in
                Token(
                    id: UUID(),
                    userID: UUID(),
                    tokenHash: "pgd_mocktoken1234567890abcdef",
                    label: "some-usage",
                    expiresAt: nil
                )
            },
            get: { _ in nil },
            findByLabel: { _, _, _ in nil },
            listUserTokens: { _, _ in [] },
            revokeToken: { _ in },
            revokeByHash: { _ in },
            markTokenUse: { _, _, _ in
                User(id: UUID(), username: "mock-user", passwordHash: "", role: .user)
            }
        )
    }

    private static func generateToken(length: Int = 32) -> String {
        let randomPart = [UInt8].random(count: length).base64
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "pgd_\(randomPart)"
    }
}
