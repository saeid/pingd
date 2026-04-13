@testable import pingd
import Testing
import VaporTesting

extension PingdTests {
    @Test("Users: GET /users as admin returns all users")
    func listUsersAsAdmin() async throws {
        try await withApp { app in
            let session = try await login(app, username: "jinx", password: "hunter2")
            try await app.testing().test(
                .GET, "users",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let users = try res.content.decode([UserResponse].self)
                    #expect(users.count == User.allUsers.count + 1) // +1 for SeedAdminUser migration
                }
            )
        }
    }

    @Test("Users: GET /users as non-admin returns 403")
    func listUsersAsNonAdmin() async throws {
        try await withApp { app in
            let session = try await login(app, username: "vi", password: "password1")
            try await app.testing().test(
                .GET, "users",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                },
                afterResponse: { res in
                    #expect(res.status == .forbidden)
                }
            )
        }
    }

    @Test("Users: POST /users creates new user as admin")
    func createUser() async throws {
        try await withApp { app in
            let session = try await login(app, username: "jinx", password: "hunter2")
            try await app.testing().test(
                .POST, "users",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(CreateUserRequest(username: "newuser", password: "pass123", role: .user))
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let user = try res.content.decode(UserResponse.self)
                    #expect(user.username == "newuser")
                    #expect(user.role == .user)
                }
            )
        }
    }

    @Test("Users: GET /users/:username as self returns user")
    func getUserAsSelf() async throws {
        try await withApp { app in
            let session = try await login(app, username: "vi", password: "password1")
            try await app.testing().test(
                .GET, "users/vi",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let user = try res.content.decode(UserResponse.self)
                    #expect(user.username == "vi")
                }
            )
        }
    }

    @Test("Users: GET /users/:username as other non-admin returns 403")
    func getUserAsOtherNonAdmin() async throws {
        try await withApp { app in
            let session = try await login(app, username: "vi", password: "password1")
            try await app.testing().test(
                .GET, "users/vander",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                },
                afterResponse: { res in
                    #expect(res.status == .forbidden)
                }
            )
        }
    }

    @Test("Users: DELETE /users/:username as admin deletes user")
    func deleteUser() async throws {
        try await withApp { app in
            let session = try await login(app, username: "jinx", password: "hunter2")
            try await app.testing().test(
                .DELETE, "users/vander",
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
