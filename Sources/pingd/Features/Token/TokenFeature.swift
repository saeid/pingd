import Foundation

struct TokenFeature {
    let createUserToken: @Sendable (User, String, String?, Date?) async throws -> Token
    let listUserTokens: @Sendable (User, String) async throws -> [Token]
    let revokeToken: @Sendable (User, UUID) async throws -> Void
}

extension TokenFeature {
    static func live(tokenClient: TokenClient, userClient: UserClient) -> Self {
        TokenFeature(
            createUserToken: { user, username, label, expiryDate in
                try userClient.checkAdminPermission(for: user)
                let userID = try await userClient.getUserId(for: username)
                let token = try await tokenClient.createToken(userID, label, expiryDate)
                return token
            }, listUserTokens: { user, username in
                try userClient.checkAdminPermission(for: user)
                let userID = try await userClient.getUserId(for: username)
                return try await tokenClient.listUserTokens(userID)
            }, revokeToken: { user, tokenId in
                try userClient.checkAdminPermission(for: user)
                try await tokenClient.revokeToken(tokenId)
            })
    }
}
