@testable import pingd
import Testing
import VaporTesting

extension PingdTests {
    @Test("Auth: Login with valid credentials returns token")
    func loginSuccess() async throws {
        try await withApp { app in
            try await app.testing().test(
                .POST, "auth/login",
                beforeRequest: { req in
                    try req.content.encode(LoginRequest(username: "jinx", password: "hunter2", label: nil))
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let body = try res.content.decode(LoginResponse.self)
                    #expect(body.username == "jinx")
                    #expect(!body.token.isEmpty)
                }
            )
        }
    }

    @Test("Auth: Login with wrong password returns 401")
    func loginWrongPassword() async throws {
        try await withApp { app in
            try await app.testing().test(
                .POST, "auth/login",
                beforeRequest: { req in
                    try req.content.encode(LoginRequest(username: "jinx", password: "wrongpassword", label: nil))
                },
                afterResponse: { res in
                    #expect(res.status == .unauthorized)
                }
            )
        }
    }

    @Test("Auth: Login with unknown username returns 401")
    func loginUnknownUser() async throws {
        try await withApp { app in
            try await app.testing().test(
                .POST, "auth/login",
                beforeRequest: { req in
                    try req.content.encode(LoginRequest(username: "nobody", password: "password", label: nil))
                },
                afterResponse: { res in
                    #expect(res.status == .unauthorized)
                }
            )
        }
    }

    @Test("Auth: GET /me with valid token returns current user")
    func meSuccess() async throws {
        try await withApp { app in
            let session = try await login(app, username: "jinx", password: "hunter2")
            try await app.testing().test(
                .GET, "me",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let body = try res.content.decode(UserResponse.self)
                    #expect(body.username == "jinx")
                }
            )
        }
    }

    @Test("Auth: GET /me without token returns 401")
    func meUnauthorized() async throws {
        try await withApp { app in
            try await app.testing().test(
                .GET, "me",
                afterResponse: { res in
                    #expect(res.status == .unauthorized)
                }
            )
        }
    }

    @Test("Auth: Logout revokes token")
    func logout() async throws {
        try await withApp { app in
            let session = try await login(app, username: "jinx", password: "hunter2")

            try await app.testing().test(
                .DELETE, "auth/logout",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                },
                afterResponse: { res in
                    #expect(res.status == .noContent)
                }
            )

            try await app.testing().test(
                .GET, "me",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                },
                afterResponse: { res in
                    #expect(res.status == .unauthorized)
                }
            )
        }
    }
}
