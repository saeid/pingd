@testable import pingd
import Testing
import VaporTesting

extension PingdTests {
    @Test("Topics: GET /topics as anonymous returns only publicRead topics")
    func listTopicsAnonymous() async throws {
        try await withApp { app in
            try await seedTopics(app)
            try await app.testing().test(
                .GET, "topics",
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let topics = try res.content.decode([TopicResponse].self)
                    #expect(topics.allSatisfy { $0.publicRead })
                    #expect(topics.map(\.name) == ["public-topic"])
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

    @Test("Topics: GET /topics as authenticated without permission shows only publicRead topics")
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
                    #expect(topics.map(\.name) == ["public-topic"])
                }
            )
        }
    }

    @Test("Topics: GET /topics as authenticated with matching permission includes restricted topic")
    func listTopicsAuthenticatedWithPermission() async throws {
        try await withApp { app in
            try await seedTopics(app)
            try await savePermission(app, username: "vi", accessLevel: .readOnly, topicPattern: "restricted-topic")

            let session = try await login(app, username: "vi", password: "password1")
            try await app.testing().test(
                .GET, "topics",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let topics = try res.content.decode([TopicResponse].self)
                    #expect(topics.map(\.name).sorted() == ["public-topic", "restricted-topic"])
                }
            )
        }
    }

    @Test("Topics: GET /topics as guest returns only publicRead topics even with permission")
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
                topicPattern: "restricted-topic"
            ).save(on: app.db)

            try await app.testing().test(
                .GET, "topics",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let topics = try res.content.decode([TopicResponse].self)
                    #expect(topics.map(\.name) == ["public-topic"])
                }
            )
        }
    }

    @Test("Topics: GET /topics/:name publicRead topic as anonymous returns topic")
    func getPublicTopicAnonymous() async throws {
        try await withApp { app in
            try await seedTopics(app)
            try await app.testing().test(
                .GET, "topics/public-topic",
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let topic = try res.content.decode(TopicResponse.self)
                    #expect(topic.name == "public-topic")
                    #expect(topic.publicRead)
                }
            )
        }
    }

    @Test("Topics: GET /topics/:name private topic as guest without share token returns 403")
    func getPrivateTopicGuestRequiresShareToken() async throws {
        try await withApp { app in
            try await seedTopics(app)
            let session = try await loginGuest(app)
            try await app.testing().test(
                .GET, "topics/private-topic",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                },
                afterResponse: { res in
                    #expect(res.status == .forbidden)
                }
            )
        }
    }

    @Test("Topics: GET /topics/:name private topic with valid share token returns topic")
    func getPrivateTopicWithShareToken() async throws {
        try await withApp { app in
            try await seedTopics(app)
            let raw = try await createShareToken(app, topicName: "private-topic", accessLevel: .readOnly)
            try await app.testing().test(
                .GET, "topics/private-topic",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-Topic-Token", value: raw)
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let topic = try res.content.decode(TopicResponse.self)
                    #expect(topic.name == "private-topic")
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

    @Test("Topics: GET /topics/:name private topic with invalid share token returns 403")
    func getPrivateTopicInvalidShareToken() async throws {
        try await withApp { app in
            try await seedTopics(app)
            try await app.testing().test(
                .GET, "topics/private-topic",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-Topic-Token", value: "tk_bogus")
                },
                afterResponse: { res in
                    #expect(res.status == .forbidden)
                }
            )
        }
    }

    @Test("Topics: GET /topics/:name private topic with expired share token returns 403")
    func getPrivateTopicExpiredShareToken() async throws {
        try await withApp { app in
            try await seedTopics(app)
            let raw = try await createShareToken(
                app,
                topicName: "private-topic",
                accessLevel: .readOnly,
                expiresAt: Date().addingTimeInterval(-60)
            )
            try await app.testing().test(
                .GET, "topics/private-topic",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-Topic-Token", value: raw)
                },
                afterResponse: { res in
                    #expect(res.status == .forbidden)
                }
            )
        }
    }

    @Test("Topics: GET /topics/:name private topic as owner returns topic")
    func getPrivateTopicAsOwner() async throws {
        try await withApp { app in
            let vander = try await requireUser(app, username: "vander")
            let topic = Topic(
                name: "vander-private",
                ownerUserID: try vander.requireID(),
                publicRead: false,
                publicPublish: false
            )
            try await topic.save(on: app.db)

            let session = try await login(app, username: "vander", password: "letmein")
            try await app.testing().test(
                .GET, "topics/vander-private",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let response = try res.content.decode(TopicResponse.self)
                    #expect(response.name == "vander-private")
                    #expect(response.publicRead == false)
                }
            )
        }
    }

    @Test("Topics: GET /topics/:name private topic as admin non-owner returns topic")
    func getPrivateTopicAsAdminNonOwner() async throws {
        try await withApp { app in
            try await seedTopics(app)
            let session = try await login(app, username: "silco", password: "secret123")
            try await app.testing().test(
                .GET, "topics/restricted-topic",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let response = try res.content.decode(TopicResponse.self)
                    #expect(response.name == "restricted-topic")
                }
            )
        }
    }

    @Test("Topics: POST /topics creates topic with publicRead/publicPublish")
    func createTopic() async throws {
        try await withApp { app in
            let session = try await login(app, username: "jinx", password: "hunter2")
            try await app.testing().test(
                .POST, "topics",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(CreateTopicRequest(name: "new-topic", publicRead: true, publicPublish: false))
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let topic = try res.content.decode(TopicResponse.self)
                    #expect(topic.name == "new-topic")
                    #expect(topic.publicRead)
                    #expect(topic.publicPublish == false)
                }
            )
        }
    }

    @Test("Topics: POST /topics defaults publicRead/publicPublish to false")
    func createTopicDefaultsToPrivate() async throws {
        try await withApp { app in
            let session = try await login(app, username: "jinx", password: "hunter2")
            try await app.testing().test(
                .POST, "topics",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(CreateTopicRequest(name: "default-topic", publicRead: nil, publicPublish: nil))
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let topic = try res.content.decode(TopicResponse.self)
                    #expect(topic.name == "default-topic")
                    #expect(topic.publicRead == false)
                    #expect(topic.publicPublish == false)
                }
            )
        }
    }

    @Test("Topics: POST /topics applies PINGD_DEFAULT_PUBLIC_READ when body omits publicRead")
    func createTopicAppliesConfiguredDefaultPublicRead() async throws {
        try await withApp { app in
            app.appConfig = AppConfig(
                rateLimit: app.appConfig.rateLimit,
                webhookRateLimit: app.appConfig.webhookRateLimit,
                cors: app.appConfig.cors,
                allowRegistration: app.appConfig.allowRegistration,
                guestEnabled: app.appConfig.guestEnabled,
                defaultPublicRead: true,
                defaultPublicPublish: false
            )
            let session = try await login(app, username: "jinx", password: "hunter2")
            try await app.testing().test(
                .POST, "topics",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(CreateTopicRequest(name: "topic-with-defaults", publicRead: nil, publicPublish: nil))
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let topic = try res.content.decode(TopicResponse.self)
                    #expect(topic.publicRead)
                    #expect(topic.publicPublish == false)
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
                    try req.content.encode(CreateTopicRequest(name: "new-topic", publicRead: true, publicPublish: false))
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
                    try req.content.encode(CreateTopicRequest(name: "guest-topic", publicRead: true, publicPublish: false))
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
                    try req.content.encode(CreateTopicRequest(name: "ab", publicRead: true, publicPublish: false))
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
                    try req.content.encode(CreateTopicRequest(name: "public-topic", publicRead: true, publicPublish: false))
                },
                afterResponse: { res in
                    #expect(res.status == .badRequest)
                }
            )
        }
    }

    @Test("Topics: PATCH /topics/:name as owner updates publicRead")
    func updateTopicAsOwner() async throws {
        try await withApp { app in
            try await seedTopics(app)
            let session = try await login(app, username: "jinx", password: "hunter2")
            try await app.testing().test(
                .PATCH, "topics/public-topic",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(UpdateTopicRequest(publicRead: false, publicPublish: nil))
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let topic = try res.content.decode(TopicResponse.self)
                    #expect(topic.publicRead == false)
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
                .PATCH, "topics/public-topic",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(UpdateTopicRequest(publicRead: false, publicPublish: nil))
                },
                afterResponse: { res in
                    #expect(res.status == .forbidden)
                }
            )
        }
    }

    @Test("Topics: PATCH /topics/:name as non-owner with rw permission returns 403")
    func updateTopicAsOtherWithReadWritePermission() async throws {
        try await withApp { app in
            try await seedTopics(app)
            try await savePermission(app, username: "vi", accessLevel: .readWrite, topicPattern: "restricted-topic")
            let session = try await login(app, username: "vi", password: "password1")
            try await app.testing().test(
                .PATCH, "topics/restricted-topic",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(UpdateTopicRequest(publicRead: true, publicPublish: nil))
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
                .DELETE, "topics/public-topic",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                },
                afterResponse: { res in
                    #expect(res.status == .noContent)
                }
            )
        }
    }

    @Test("Topics: DELETE /topics/:name as non-owner with rw permission returns 403")
    func deleteTopicAsOtherWithReadWritePermission() async throws {
        try await withApp { app in
            try await seedTopics(app)
            try await savePermission(app, username: "vi", accessLevel: .readWrite, topicPattern: "restricted-topic")
            let session = try await login(app, username: "vi", password: "password1")
            try await app.testing().test(
                .DELETE, "topics/restricted-topic",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                },
                afterResponse: { res in
                    #expect(res.status == .forbidden)
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
                .DELETE, "topics/public-topic",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                },
                afterResponse: { res in
                    #expect(res.status == .forbidden)
                }
            )
        }
    }

    @Test("Topics: GET /topics/:name/stats for nonexistent topic returns 404")
    func topicStatsNotFound() async throws {
        try await withApp { app in
            let session = try await login(app, username: "jinx", password: "hunter2")
            try await app.testing().test(
                .GET, "topics/does-not-exist/stats",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                },
                afterResponse: { res in
                    #expect(res.status == .notFound)
                }
            )
        }
    }

    @Test("Topics: GET /topics/:name/stats as guest returns 403")
    func topicStatsAsGuest() async throws {
        try await withApp { app in
            try await seedTopics(app)
            let session = try await loginGuest(app)
            try await app.testing().test(
                .GET, "topics/public-topic/stats",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                },
                afterResponse: { res in
                    #expect(res.status == .forbidden)
                }
            )
        }
    }

    @Test("Topics: GET /topics/:name/stats as anonymous returns 401")
    func topicStatsAnonymous() async throws {
        try await withApp { app in
            try await seedTopics(app)
            try await app.testing().test(
                .GET, "topics/public-topic/stats",
                afterResponse: { res in
                    #expect(res.status == .unauthorized)
                }
            )
        }
    }
}
