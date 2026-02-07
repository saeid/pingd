import Foundation
import Vapor
import Fluent

struct TokenClient {
    let createToken: @Sendable (UUID, String?, Date?) async throws -> Token
    let listUserTokens: @Sendable (UUID) async throws -> [Token]
    let revokeToken: @Sendable (UUID) async throws -> Void
    let markTokenUse: @Sendable (String, String, Date) async throws -> Void
}

extension TokenClient {
    static func live(app: Application, userClient: UserClient) -> Self {
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
            listUserTokens: { userId in
                let tokens = try await Token.query(on: app.db)
                    .filter(\.$user.$id == userId)
                    .filter(\.$expiresAt > Date())
                    .all()
                return tokens
            },
            revokeToken: { tokenId in
                guard let token = try await Token.find(tokenId, on: app.db) else {
                    return
                }
                try await token.delete(on: app.db)
            },
            markTokenUse: { token, ip, now in
                guard let token = try await Token.query(on: app.db).(token, on: app.db) else {
                    return
                }
                token.lastUsedAt = now
                token.lastUsedIp = ip
                try await token.save(on: app.db)
            }
        )
    }

    static func mock() -> Self {
        TokenClient(
            createToken: { _, _, _ in
                Token(
                    id: UUID(),
                    userID: UUID(),
                    tokenHash: "mock-token-123",
                    label: "some-usage",
                    expiresAt: nil
                )
            },
            listUserTokens: { _ in [] },
            revokeToken: { _ in },
            markTokenUse: { _, _, _ in }
        )
    }

    private static func generateToken(length: Int = 32) -> String {
        [UInt8].random(count: 32).base64
    }
}
