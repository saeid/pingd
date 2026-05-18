@testable import pingd
import Testing
import VaporTesting

extension PingdTests {
    @Test("Topics: GET /users/:username/topics returns caller's own topics")
    func listOwnedTopicsForSelf() async throws {
        try await withApp { app in
            let vi = try await requireUser(app, username: "vi")
            try await Topic(name: "vi-topic1", ownerUserID: try vi.requireID()).save(on: app.db)
            try await Topic(name: "vi-topic2", ownerUserID: try vi.requireID()).save(on: app.db)
            try await seedTopics(app)

            let session = try await login(app, username: "vi", password: "password1")
            try await app.testing().test(
                .GET, "users/vi/topics",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let topics = try res.content.decode([TopicResponse].self)
                    #expect(topics.map(\.name).sorted() == ["vi-topic1", "vi-topic2"])
                }
            )
        }
    }

    @Test("Topics: GET /users/:username/topics returns empty list when user owns nothing")
    func listOwnedTopicsEmpty() async throws {
        try await withApp { app in
            try await seedTopics(app)

            let session = try await login(app, username: "vi", password: "password1")
            try await app.testing().test(
                .GET, "users/vi/topics",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let topics = try res.content.decode([TopicResponse].self)
                    #expect(topics.isEmpty)
                }
            )
        }
    }

    @Test("Topics: GET /users/:username/topics returns 403 for another user")
    func listOwnedTopicsForOtherUserForbidden() async throws {
        try await withApp { app in
            let session = try await login(app, username: "vi", password: "password1")
            try await app.testing().test(
                .GET, "users/vander/topics",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                },
                afterResponse: { res in
                    #expect(res.status == .forbidden)
                }
            )
        }
    }

    @Test("Topics: GET /users/:username/topics as admin lists any user's owned topics")
    func listOwnedTopicsForOtherUserAsAdmin() async throws {
        try await withApp { app in
            let vi = try await requireUser(app, username: "vi")
            try await Topic(name: "vi-topic1", ownerUserID: try vi.requireID()).save(on: app.db)

            let session = try await login(app, username: "jinx", password: "hunter2")
            try await app.testing().test(
                .GET, "users/vi/topics",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let topics = try res.content.decode([TopicResponse].self)
                    #expect(topics.map(\.name) == ["vi-topic1"])
                }
            )
        }
    }

    @Test("Topics: GET /users/:username/topics without token returns 401")
    func listOwnedTopicsUnauthenticated() async throws {
        try await withApp { app in
            try await app.testing().test(
                .GET, "users/vi/topics",
                afterResponse: { res in
                    #expect(res.status == .unauthorized)
                }
            )
        }
    }

    @Test("Topics: GET /users/:username/topics returns 404 when admin asks for unknown user")
    func listOwnedTopicsUnknownUser() async throws {
        try await withApp { app in
            let session = try await login(app, username: "jinx", password: "hunter2")
            try await app.testing().test(
                .GET, "users/ghost/topics",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                },
                afterResponse: { res in
                    #expect(res.status == .notFound)
                }
            )
        }
    }
}
