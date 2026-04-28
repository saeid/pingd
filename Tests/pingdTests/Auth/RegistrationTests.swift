@testable import pingd
import Testing
import VaporTesting

extension PingdTests {
    private func enableRegistration(_ app: Application) {
        app.appConfig = AppConfig(
            rateLimit: app.appConfig.rateLimit,
            webhookRateLimit: app.appConfig.webhookRateLimit,
            cors: app.appConfig.cors,
            allowRegistration: true
        )
    }

    @Test("Register: creates user and returns token")
    func registerSuccess() async throws {
        try await withApp { app in
            enableRegistration(app)

            try await app.testing().test(
                .POST, "auth/register",
                beforeRequest: { req in
                    try req.content.encode(RegisterRequest(username: "newuser", password: "password123", label: "my-server"))
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let body = try res.content.decode(LoginResponse.self)
                    #expect(body.username == "newuser")
                    #expect(!body.token.isEmpty)
                }
            )
        }
    }

    @Test("Register: duplicate username returns 400")
    func registerDuplicateUsername() async throws {
        try await withApp { app in
            enableRegistration(app)

            try await app.testing().test(
                .POST, "auth/register",
                beforeRequest: { req in
                    try req.content.encode(RegisterRequest(username: "jinx", password: "password123", label: nil))
                },
                afterResponse: { res in
                    #expect(res.status == .badRequest)
                }
            )
        }
    }

    @Test("Register: short username returns 400")
    func registerShortUsername() async throws {
        try await withApp { app in
            enableRegistration(app)

            try await app.testing().test(
                .POST, "auth/register",
                beforeRequest: { req in
                    try req.content.encode(RegisterRequest(username: "ab", password: "password123", label: nil))
                },
                afterResponse: { res in
                    #expect(res.status == .badRequest)
                }
            )
        }
    }

    @Test("Register: short password returns 400")
    func registerShortPassword() async throws {
        try await withApp { app in
            enableRegistration(app)

            try await app.testing().test(
                .POST, "auth/register",
                beforeRequest: { req in
                    try req.content.encode(RegisterRequest(username: "newuser", password: "short", label: nil))
                },
                afterResponse: { res in
                    #expect(res.status == .badRequest)
                }
            )
        }
    }

    @Test("Register: disabled by default returns 403")
    func registerDisabled() async throws {
        try await withApp { app in
            try await app.testing().test(
                .POST, "auth/register",
                beforeRequest: { req in
                    try req.content.encode(RegisterRequest(username: "newuser", password: "password123", label: nil))
                },
                afterResponse: { res in
                    #expect(res.status == .forbidden)
                }
            )
        }
    }
}
