@testable import pingd
import Testing
import VaporTesting

extension PingdTests {
    @Test("Tokens: POST /users/:username/tokens creates token")
    func createToken() async throws {
        try await withApp { app in
            let session = try await login(app, username: "jinx", password: "hunter2")
            try await app.testing().test(
                .POST, "users/vi/tokens",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(CreateTokenRequest(label: "test-token", expiresAt: nil))
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let token = try res.content.decode(TokenResponse.self)
                    #expect(token.label == "test-token")
                }
            )
        }
    }

    @Test("Tokens: GET /users/:username/tokens lists tokens")
    func listTokens() async throws {
        try await withApp { app in
            let session = try await login(app, username: "jinx", password: "hunter2")
            try await app.testing().test(
                .GET, "users/jinx/tokens",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let tokens = try res.content.decode([TokenResponse].self)
                    #expect(tokens.count >= 1)
                }
            )
        }
    }

    @Test("Tokens: DELETE /tokens/:id revokes token")
    func revokeToken() async throws {
        try await withApp { app in
            let session = try await login(app, username: "jinx", password: "hunter2")

            var createdToken: TokenResponse?
            try await app.testing().test(
                .POST, "users/jinx/tokens",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(CreateTokenRequest(label: "to-revoke", expiresAt: nil))
                },
                afterResponse: { res in
                    createdToken = try res.content.decode(TokenResponse.self)
                }
            )

            let tokenID = try #require(createdToken?.id)
            try await app.testing().test(
                .DELETE, "tokens/\(tokenID)",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                },
                afterResponse: { res in
                    #expect(res.status == .noContent)
                }
            )
        }
    }
}
