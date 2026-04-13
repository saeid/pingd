import Vapor

enum AuthError: AbortError {
    case invalidCredentials

    var status: HTTPResponseStatus { .unauthorized }
    var reason: String {
        switch self {
        case .invalidCredentials: "Invalid credentials"
        }
    }
}

struct AuthFeature {
    let doBasicAuth: @Sendable (String, String) async throws -> User
    let doTokenAuth: @Sendable (String, String) async throws -> User
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
                return user
            },
            doTokenAuth: { token, ip in
                try await tokenClient.markTokenUse(token, ip, now())
            }
        )
    }

    static func mock() -> AuthFeature {
        AuthFeature(
            doBasicAuth: { username, _ in
                User(id: UUID(), username: username, passwordHash: "", role: .user)
            },
            doTokenAuth: { _, _ in
                User(id: UUID(), username: "mock-user", passwordHash: "", role: .user)
            }
        )
    }
}
