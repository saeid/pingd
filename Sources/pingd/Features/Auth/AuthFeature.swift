import Foundation

enum AuthError: Error {
    case invalidCredentials
}

struct AuthFeature {
    let doBasicAuth: @Sendable (String, String) async throws -> Bool
    let doTokenAuth: @Sendable (String, String) async throws -> Bool
}

extension AuthFeature {
    static func live(
        userClient: UserClient,
        authClient: AuthClient,
        tokenClient: TokenClient,
        now: @escaping @Sendable () -> Date
    ) -> AuthFeature {
        AuthFeature(
            doBasicAuth: { username, password in
                guard let user = try await userClient.getByUsername(username),
                      try authClient.verifyPassword(password, user.passwordHash)
                else {
                    throw AuthError.invalidCredentials
                }
                return true
            },
            doTokenAuth: { token, ip in
                guard let token = try await tokenClient.markTokenUse(token, ip, now()) else {
                    return nil
                }
                return try await userClient.getByID(token.$user.id)
            }
        )
    }

    static func mock() -> AuthFeature {
        AuthFeature(
            login: { username, _ in
                let id = UUID()
                let user = User(id: id, username: username, passwordHash: "", role: .user)
                let token = UserToken(
                    id: UUID(),
                    value: "mock-token",
                    userID: id,
                    createdAt: Date(),
                    expiresAt: nil,
                    lastAccessAt: nil,
                    lastAccessIP: nil
                )
                return (user, token)
            },
            resolveUserFromToken: { _, _ in nil }
        )
    }
}
