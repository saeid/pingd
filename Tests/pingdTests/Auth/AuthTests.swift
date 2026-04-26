import Fluent
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
                    try req.content.encode(LoginRequest(username: "jinx", password: "hunter2", label: "test"))
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
                    try req.content.encode(LoginRequest(username: "jinx", password: "wrongpassword", label: "test"))
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
                    try req.content.encode(LoginRequest(username: "nobody", password: "password", label: "test"))
                },
                afterResponse: { res in
                    #expect(res.status == .unauthorized)
                }
            )
        }
    }

    @Test("Auth: Guest login returns token and /me returns guest user")
    func guestLogin() async throws {
        try await withApp { app in
            var session: LoginResponse?
            try await app.testing().test(
                .POST, "auth/guest",
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let body = try res.content.decode(LoginResponse.self)
                    #expect(body.username.hasPrefix("guest-"))
                    #expect(!body.token.isEmpty)
                    session = body
                }
            )

            let guestSession = try #require(session)
            try await app.testing().test(
                .GET, "me",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: guestSession.token)
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let user = try res.content.decode(UserResponse.self)
                    #expect(user.id == guestSession.userID)
                    #expect(user.username == guestSession.username)
                    #expect(user.role == .guest)
                }
            )
        }
    }

    @Test("Auth: Guest login creates non-expiring token")
    func guestLoginCreatesNonExpiringToken() async throws {
        try await withApp { app in
            let session = try await loginGuest(app)
            let token = try await Token.query(on: app.db)
                .filter(\.$tokenHash == session.token)
                .first()
            #expect(token?.expiresAt == nil)
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

    @Test("Auth: Logout with push token only deactivates current user's device")
    func logoutWithOtherUsersPushTokenDoesNotDeactivateDevice() async throws {
        try await withApp { app in
            try await seedDevices(app)
            let vanderSession = try await login(app, username: "vander", password: "letmein")
            try await app.testing().test(
                .DELETE, "auth/logout?pushToken=token-vi-iphone",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: vanderSession.token)
                },
                afterResponse: { res in
                    #expect(res.status == .noContent)
                }
            )

            let viSession = try await login(app, username: "vi", password: "password1")
            try await app.testing().test(
                .GET, "devices",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: viSession.token)
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let devices = try res.content.decode([DeviceResponse].self)
                    #expect(devices.count == 1)
                    #expect(devices[0].isActive == true)
                }
            )
        }
    }
}
