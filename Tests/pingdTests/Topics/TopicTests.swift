@testable import pingd
import Testing
import VaporTesting

extension PingdTests {
    @Test("Topics: GET /topics as anonymous returns only open topics")
    func listTopicsAnonymous() async throws {
        try await withApp { app in
            try await seedTopics(app)
            try await app.testing().test(
                .GET, "topics",
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let topics = try res.content.decode([TopicResponse].self)
                    #expect(topics.allSatisfy { $0.visibility == .open })
                }
            )
        }
    }

    @Test("Topics: GET /topics as admin returns all topics")
    func listTopicsAsAdmin() async throws {
        try await withApp { app in
            try await seedTopics(app)
            let session = try await login(app, username: "jinx", password: "hunter2")
            try await app.testing().test(
                .GET, "topics",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let topics = try res.content.decode([TopicResponse].self)
                    #expect(topics.count == 3)
                }
            )
        }
    }

    @Test("Topics: GET /topics as authenticated without permission hides private topics")
    func listTopicsAuthenticatedWithoutPermission() async throws {
        try await withApp { app in
            try await seedTopics(app)
            let session = try await login(app, username: "vi", password: "password1")
            try await app.testing().test(
                .GET, "topics",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let topics = try res.content.decode([TopicResponse].self)
                    #expect(topics.map(\.name).sorted() == ["open-topic", "protected-topic"])
                }
            )
        }
    }

    @Test("Topics: GET /topics as authenticated with matching permission includes private topic")
    func listTopicsAuthenticatedWithPermission() async throws {
        try await withApp { app in
            try await seedTopics(app)
            let vi = try #require(
                try await User.query(on: app.db)
                    .filter(\.$username, .equal, "vi")
                    .first()
            )
            let permission = Permission(
                scope: .user,
                accessLevel: .readOnly,
                userId: try vi.requireID(),
                topicPattern: "private-topic"
            )
            try await permission.save(on: app.db)

            let session = try await login(app, username: "vi", password: "password1")
            try await app.testing().test(
                .GET, "topics",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let topics = try res.content.decode([TopicResponse].self)
                    #expect(topics.map(\.name).sorted() == ["open-topic", "private-topic", "protected-topic"])
                }
            )
        }
    }

    @Test("Topics: GET /topics as guest returns only open topics even with permission")
    func listTopicsGuestIgnoresPermissions() async throws {
        try await withApp { app in
            try await seedTopics(app)
            let session = try await loginGuest(app)
            let guest = try #require(
                try await User.query(on: app.db)
                    .filter(\.$username, .equal, session.username)
                    .first()
            )
            try await Permission(
                scope: .user,
                accessLevel: .readWrite,
                userId: try guest.requireID(),
                topicPattern: "private-topic"
            ).save(on: app.db)

            try await app.testing().test(
                .GET, "topics",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let topics = try res.content.decode([TopicResponse].self)
                    #expect(topics.map(\.name) == ["open-topic"])
                }
            )
        }
    }

    @Test("Topics: GET /topics/:name open topic as anonymous returns topic")
    func getOpenTopicAnonymous() async throws {
        try await withApp { app in
            try await seedTopics(app)
            try await app.testing().test(
                .GET, "topics/open-topic",
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let topic = try res.content.decode(TopicResponse.self)
                    #expect(topic.name == "open-topic")
                }
            )
        }
    }

    @Test("Topics: GET /topics/:name protected topic as guest requires password")
    func getProtectedTopicGuestRequiresPassword() async throws {
        try await withApp { app in
            try await seedTopics(app)
            let session = try await loginGuest(app)
            try await app.testing().test(
                .GET, "topics/protected-topic",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                },
                afterResponse: { res in
                    #expect(res.status == .forbidden)
                }
            )

            try await app.testing().test(
                .GET, "topics/protected-topic",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    req.headers.replaceOrAdd(name: "X-Topic-Password", value: protectedTopicPassword)
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let topic = try res.content.decode(TopicResponse.self)
                    #expect(topic.name == "protected-topic")
                }
            )
        }
    }

    @Test("Topics: GET /topics/:name protected topic as anonymous returns 403")
    func getProtectedTopicAnonymous() async throws {
        try await withApp { app in
            try await seedTopics(app)
            try await app.testing().test(
                .GET, "topics/protected-topic",
                afterResponse: { res in
                    #expect(res.status == .forbidden)
                }
            )
        }
    }

    @Test("Topics: GET /topics/:name protected topic as anonymous with password returns topic")
    func getProtectedTopicAnonymousWithPassword() async throws {
        try await withApp { app in
            try await seedTopics(app)
            try await app.testing().test(
                .GET, "topics/protected-topic",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-Topic-Password", value: protectedTopicPassword)
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let topic = try res.content.decode(TopicResponse.self)
                    #expect(topic.name == "protected-topic")
                    #expect(topic.hasPassword)
                }
            )
        }
    }

    @Test("Topics: GET /topics/:name protected topic as anonymous with wrong password returns 403")
    func getProtectedTopicAnonymousWithWrongPassword() async throws {
        try await withApp { app in
            try await seedTopics(app)
            try await app.testing().test(
                .GET, "topics/protected-topic",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-Topic-Password", value: "wrong-password")
                },
                afterResponse: { res in
                    #expect(res.status == .forbidden)
                }
            )
        }
    }

    @Test("Topics: GET /topics/:name private topic as anonymous returns 403")
    func getPrivateTopicAnonymous() async throws {
        try await withApp { app in
            try await seedTopics(app)
            try await app.testing().test(
                .GET, "topics/private-topic",
                afterResponse: { res in
                    #expect(res.status == .forbidden)
                }
            )
        }
    }

    @Test("Topics: GET /topics/:name private topic as anonymous with password returns 403")
    func getPrivateTopicAnonymousWithPassword() async throws {
        try await withApp { app in
            try await seedTopics(app)
            try await app.testing().test(
                .GET, "topics/private-topic",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-Topic-Password", value: privateTopicPassword)
                },
                afterResponse: { res in
                    #expect(res.status == .forbidden)
                }
            )
        }
    }

    @Test("Topics: GET /topics/:name private topic as anonymous with wrong password returns 403")
    func getPrivateTopicAnonymousWithWrongPassword() async throws {
        try await withApp { app in
            try await seedTopics(app)
            try await app.testing().test(
                .GET, "topics/private-topic",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-Topic-Password", value: "wrong-password")
                },
                afterResponse: { res in
                    #expect(res.status == .forbidden)
                }
            )
        }
    }

    @Test("Topics: POST /topics creates topic")
    func createTopic() async throws {
        try await withApp { app in
            let session = try await login(app, username: "jinx", password: "hunter2")
            try await app.testing().test(
                .POST, "topics",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(CreateTopicRequest(name: "new-topic", visibility: .open, password: nil))
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let topic = try res.content.decode(TopicResponse.self)
                    #expect(topic.name == "new-topic")
                    #expect(topic.visibility == .open)
                    #expect(topic.hasPassword == false)
                }
            )
        }
    }

    @Test("Topics: POST /topics with password stores password hash")
    func createTopicWithPassword() async throws {
        try await withApp { app in
            let session = try await login(app, username: "jinx", password: "hunter2")
            try await app.testing().test(
                .POST, "topics",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(CreateTopicRequest(name: "locked-topic", visibility: .protected, password: "topic-secret"))
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let topic = try res.content.decode(TopicResponse.self)
                    #expect(topic.name == "locked-topic")
                    #expect(topic.hasPassword)
                }
            )
        }
    }

    @Test("Topics: POST /topics as anonymous returns 401")
    func createTopicAnonymous() async throws {
        try await withApp { app in
            try await app.testing().test(
                .POST, "topics",
                beforeRequest: { req in
                    try req.content.encode(CreateTopicRequest(name: "new-topic", visibility: .open, password: nil))
                },
                afterResponse: { res in
                    #expect(res.status == .unauthorized)
                }
            )
        }
    }

    @Test("Topics: POST /topics as guest returns 403")
    func createTopicGuest() async throws {
        try await withApp { app in
            let session = try await loginGuest(app)
            try await app.testing().test(
                .POST, "topics",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(CreateTopicRequest(name: "guest-topic", visibility: .open, password: nil))
                },
                afterResponse: { res in
                    #expect(res.status == .forbidden)
                }
            )
        }
    }

    @Test("Topics: POST /topics with short name returns 400")
    func createTopicShortName() async throws {
        try await withApp { app in
            let session = try await login(app, username: "jinx", password: "hunter2")
            try await app.testing().test(
                .POST, "topics",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(CreateTopicRequest(name: "ab", visibility: .open, password: nil))
                },
                afterResponse: { res in
                    #expect(res.status == .badRequest)
                }
            )
        }
    }

    @Test("Topics: POST /topics with duplicate name returns 400")
    func createDuplicateTopic() async throws {
        try await withApp { app in
            try await seedTopics(app)
            let session = try await login(app, username: "jinx", password: "hunter2")
            try await app.testing().test(
                .POST, "topics",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(CreateTopicRequest(name: "open-topic", visibility: .open, password: nil))
                },
                afterResponse: { res in
                    #expect(res.status == .badRequest)
                }
            )
        }
    }

    @Test("Topics: PATCH /topics/:name as owner updates visibility")
    func updateTopicAsOwner() async throws {
        try await withApp { app in
            try await seedTopics(app)
            let session = try await login(app, username: "jinx", password: "hunter2")
            try await app.testing().test(
                .PATCH, "topics/open-topic",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(UpdateTopicRequest(visibility: .protected, password: nil))
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let topic = try res.content.decode(TopicResponse.self)
                    #expect(topic.visibility == .protected)
                }
            )
        }
    }

    @Test("Topics: PATCH /topics/:name empty password removes topic password")
    func updateTopicRemovesPassword() async throws {
        try await withApp { app in
            try await seedTopics(app)
            let session = try await login(app, username: "jinx", password: "hunter2")
            try await app.testing().test(
                .PATCH, "topics/protected-topic",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(UpdateTopicRequest(visibility: nil, password: ""))
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let topic = try res.content.decode(TopicResponse.self)
                    #expect(topic.hasPassword == false)
                }
            )
        }
    }

    @Test("Topics: PATCH /topics/:name as non-owner non-admin returns 403")
    func updateTopicAsOther() async throws {
        try await withApp { app in
            try await seedTopics(app)
            let session = try await login(app, username: "vi", password: "password1")
            try await app.testing().test(
                .PATCH, "topics/open-topic",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(UpdateTopicRequest(visibility: .protected, password: nil))
                },
                afterResponse: { res in
                    #expect(res.status == .forbidden)
                }
            )
        }
    }

    @Test("Topics: DELETE /topics/:name as owner deletes topic")
    func deleteTopic() async throws {
        try await withApp { app in
            try await seedTopics(app)
            let session = try await login(app, username: "jinx", password: "hunter2")
            try await app.testing().test(
                .DELETE, "topics/open-topic",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                },
                afterResponse: { res in
                    #expect(res.status == .noContent)
                }
            )
        }
    }

    @Test("Topics: DELETE /topics/:name as non-owner non-admin returns 403")
    func deleteTopicAsOther() async throws {
        try await withApp { app in
            try await seedTopics(app)
            let session = try await login(app, username: "vi", password: "password1")
            try await app.testing().test(
                .DELETE, "topics/open-topic",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                },
                afterResponse: { res in
                    #expect(res.status == .forbidden)
                }
            )
        }
    }
}
