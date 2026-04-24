import Fluent
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

    @Test("Tokens: expired token is rejected with 401")
    func expiredTokenRejected() async throws {
        try await withApp { app in
            let jinx = try await User.query(on: app.db).filter(\.$username == "jinx").first()!
            let expired = Token(
                userID: try jinx.requireID(),
                tokenHash: "expired-token-hash",
                label: "expired",
                expiresAt: Date().addingTimeInterval(-3600)
            )
            try await expired.save(on: app.db)

            try await app.testing().test(
                .GET, "me",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: "expired-token-hash")
                },
                afterResponse: { res in
                    #expect(res.status == .unauthorized)
                }
            )
        }
    }

    @Test("Tokens: expired tokens excluded from list")
    func expiredTokensExcludedFromList() async throws {
        try await withApp { app in
            let session = try await login(app, username: "jinx", password: "hunter2")
            let jinx = try await User.query(on: app.db).filter(\.$username == "jinx").first()!
            let expired = Token(
                userID: try jinx.requireID(),
                tokenHash: "expired-list-token",
                label: "should-not-appear",
                expiresAt: Date().addingTimeInterval(-3600)
            )
            try await expired.save(on: app.db)

            try await app.testing().test(
                .GET, "users/jinx/tokens",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let tokens = try res.content.decode([TokenResponse].self)
                    #expect(tokens.allSatisfy { $0.label != "should-not-appear" })
                }
            )
        }
    }

    @Test("Tokens: login with same label returns same token")
    func loginUpsertSameLabel() async throws {
        try await withApp { app in
            let first = try await login(app, username: "jinx", password: "hunter2", label: "my-device")
            let second = try await login(app, username: "jinx", password: "hunter2", label: "my-device")
            #expect(first.token == second.token)
        }
    }

    @Test("Tokens: login with different labels returns different tokens")
    func loginDifferentLabels() async throws {
        try await withApp { app in
            let web = try await login(app, username: "jinx", password: "hunter2", label: "web-ui")
            let cli = try await login(app, username: "jinx", password: "hunter2", label: "cli")
            #expect(web.token != cli.token)
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

    @Test("Tokens: user can create own token")
    func userCreateOwnToken() async throws {
        try await withApp { app in
            let session = try await login(app, username: "vi", password: "password1")
            try await app.testing().test(
                .POST, "users/vi/tokens",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(CreateTokenRequest(label: "self-service", expiresAt: nil))
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let token = try res.content.decode(TokenResponse.self)
                    #expect(token.label == "self-service")
                }
            )
        }
    }

    @Test("Tokens: user can list own tokens")
    func userListOwnTokens() async throws {
        try await withApp { app in
            let session = try await login(app, username: "vi", password: "password1")
            try await app.testing().test(
                .GET, "users/vi/tokens",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                }
            )
        }
    }

    @Test("Tokens: user cannot create token for another user")
    func userCannotCreateOtherToken() async throws {
        try await withApp { app in
            let session = try await login(app, username: "vi", password: "password1")
            try await app.testing().test(
                .POST, "users/jinx/tokens",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(CreateTokenRequest(label: "sneaky", expiresAt: nil))
                },
                afterResponse: { res in
                    #expect(res.status == .forbidden)
                }
            )
        }
    }

    @Test("Tokens: user cannot list another user's tokens")
    func userCannotListOtherTokens() async throws {
        try await withApp { app in
            let session = try await login(app, username: "vi", password: "password1")
            try await app.testing().test(
                .GET, "users/jinx/tokens",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                },
                afterResponse: { res in
                    #expect(res.status == .forbidden)
                }
            )
        }
    }

    @Test("Tokens: user can revoke own token")
    func userRevokeOwnToken() async throws {
        try await withApp { app in
            let session = try await login(app, username: "vi", password: "password1")

            var createdToken: TokenResponse?
            try await app.testing().test(
                .POST, "users/vi/tokens",
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

    @Test("Tokens: user cannot revoke another user's token")
    func userCannotRevokeOtherToken() async throws {
        try await withApp { app in
            let adminSession = try await login(app, username: "jinx", password: "hunter2")

            var createdToken: TokenResponse?
            try await app.testing().test(
                .POST, "users/jinx/tokens",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: adminSession.token)
                    try req.content.encode(CreateTokenRequest(label: "admin-token", expiresAt: nil))
                },
                afterResponse: { res in
                    createdToken = try res.content.decode(TokenResponse.self)
                }
            )

            let tokenID = try #require(createdToken?.id)
            let viSession = try await login(app, username: "vi", password: "password1")
            try await app.testing().test(
                .DELETE, "tokens/\(tokenID)",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: viSession.token)
                },
                afterResponse: { res in
                    #expect(res.status == .forbidden)
                }
            )
        }
    }
}
