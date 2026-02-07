import Vapor

struct AuthClient {
    let hashPassword: @Sendable (String) throws -> String
    let verifyPassword: @Sendable (String, String) throws -> Bool
}

extension AuthClient {
    static func live() -> AuthClient {
        AuthClient(
            hashPassword: {
                try Bcrypt.hash($0)
            },
            verifyPassword: {
                try Bcrypt.verify($0, created: $1)
            }
        )
    }

    static func mock() -> AuthClient {
        AuthClient(
            hashPassword: { "hash-\($0)" },
            verifyPassword: { _, _ in true }
        )
    }
}
