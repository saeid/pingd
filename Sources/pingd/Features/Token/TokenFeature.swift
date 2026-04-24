import Foundation
import Vapor

enum TokenError: AbortError {
    case activeSessionToken

    var status: HTTPResponseStatus {
        switch self {
        case .activeSessionToken: .badRequest
        }
    }

    var reason: String {
        switch self {
        case .activeSessionToken: "Cannot revoke the active session token"
        }
    }
}

struct TokenFeature {
    let createUserToken: @Sendable (User, String, String?, Date?) async throws -> Token
    let listUserTokens: @Sendable (User, String) async throws -> [Token]
    let revokeToken: @Sendable (User, UUID, String?) async throws -> Void
}

extension TokenFeature {
    static func live(tokenClient: TokenClient, userClient: UserClient) -> Self {
        TokenFeature(
            createUserToken: { user, username, label, expiryDate in
                try userClient.checkUserPermission(for: user, targetUser: username)
                let userID = try await userClient.getUserId(for: username)
                let token = try await tokenClient.createToken(userID, label, expiryDate)
                return token
            }, listUserTokens: { user, username in
                try userClient.checkUserPermission(for: user, targetUser: username)
                let userID = try await userClient.getUserId(for: username)
                return try await tokenClient.listUserTokens(userID)
            }, revokeToken: { user, tokenId, activeToken in
                guard let token = try await tokenClient.get(tokenId) else {
                    return
                }
                if token.tokenHash == activeToken {
                    throw TokenError.activeSessionToken
                }
                let currentUserID = try user.requireID()
                guard user.role == .admin || token.$user.id == currentUserID else {
                    throw UserError.accessDenied
                }
                try await tokenClient.revokeToken(tokenId)
            })
    }
}
