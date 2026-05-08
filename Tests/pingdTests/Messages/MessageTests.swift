import Fluent
@testable import pingd
import Testing
import VaporTesting

extension PingdTests {
    @Test("Messages: POST /topics/:name/messages on open topic as anonymous publishes")
    func publishToOpenTopicAnonymous() async throws {
        try await withApp { app in
            try await seedTopics(app)
            try await app.testing().test(
                .POST, "topics/public-topic/messages",
                beforeRequest: { req in
                    try req.content.encode(PublishMessageRequest(
                        priority: 3,
                        tags: nil,
                        payload: MessagePayload(title: "Hello", subtitle: nil, body: "World")
                    ))
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let message = try res.content.decode(MessageResponse.self)
                    #expect(message.payload.body == "World")
                    #expect(message.payload.title == "Hello")
                }
            )
        }
    }

    @Test("Messages: POST /topics/:name/messages with ttl returns expiresAt")
    func publishWithTTLReturnsExpiresAt() async throws {
        try await withApp { app in
            try await seedTopics(app)
            try await app.testing().test(
                .POST, "topics/public-topic/messages",
                beforeRequest: { req in
                    try req.content.encode(PublishMessageRequest(
                        priority: 3,
                        tags: nil,
                        payload: MessagePayload(title: nil, subtitle: nil, body: "Expires"),
                        ttl: 3_600
                    ))
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let message = try res.content.decode(MessageResponse.self)
                    let expiresAt = try #require(message.expiresAt)
                    #expect(expiresAt.timeIntervalSince(message.time) == 3_600)
                }
            )
        }
    }

    @Test("Messages: POST /topics/:name/messages rejects non-positive ttl")
    func publishRejectsNonPositiveTTL() async throws {
        try await withApp { app in
            try await seedTopics(app)
            try await app.testing().test(
                .POST, "topics/public-topic/messages",
                beforeRequest: { req in
                    try req.content.encode(PublishMessageRequest(
                        priority: 3,
                        tags: nil,
                        payload: MessagePayload(title: nil, subtitle: nil, body: "Invalid"),
                        ttl: 0
                    ))
                },
                afterResponse: { res in
                    #expect(res.status == .badRequest)
                }
            )
        }
    }

    @Test("Messages: POST /topics/:name/messages rejects ttl over 30 days")
    func publishRejectsTTLOverThirtyDays() async throws {
        try await withApp { app in
            try await seedTopics(app)
            try await app.testing().test(
                .POST, "topics/public-topic/messages",
                beforeRequest: { req in
                    try req.content.encode(PublishMessageRequest(
                        priority: 3,
                        tags: nil,
                        payload: MessagePayload(title: nil, subtitle: nil, body: "Invalid"),
                        ttl: 60 * 60 * 24 * 30 + 1
                    ))
                },
                afterResponse: { res in
                    #expect(res.status == .badRequest)
                }
            )
        }
    }

    @Test("Messages: POST /topics/:name/messages on private topic as anonymous returns 403")
    func publishToPrivateTopicAnonymous() async throws {
        try await withApp { app in
            try await seedTopics(app)
            try await app.testing().test(
                .POST, "topics/private-topic/messages",
                beforeRequest: { req in
                    try req.content.encode(PublishMessageRequest(
                        priority: 3,
                        tags: nil,
                        payload: MessagePayload(title: nil, subtitle: nil, body: "Hello")
                    ))
                },
                afterResponse: { res in
                    #expect(res.status == .forbidden)
                }
            )
        }
    }

    @Test("Messages: POST /topics/:name/messages on private topic as anonymous with valid share token publishes")
    func publishToPrivateTopicAnonymousWithShareToken() async throws {
        try await withApp { app in
            try await seedTopics(app)
            let raw = try await createShareToken(app, topicName: "private-topic", accessLevel: .writeOnly)
            try await app.testing().test(
                .POST, "topics/private-topic/messages",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-Topic-Token", value: raw)
                    try req.content.encode(PublishMessageRequest(
                        priority: 3,
                        tags: nil,
                        payload: MessagePayload(title: nil, subtitle: nil, body: "Hello")
                    ))
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                }
            )
        }
    }

    @Test("Messages: POST /topics/:name/messages on private topic as anonymous with invalid share token returns 403")
    func publishToPrivateTopicAnonymousWithInvalidShareToken() async throws {
        try await withApp { app in
            try await seedTopics(app)
            try await app.testing().test(
                .POST, "topics/private-topic/messages",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-Topic-Token", value: "tk_bogus")
                    try req.content.encode(PublishMessageRequest(
                        priority: 3,
                        tags: nil,
                        payload: MessagePayload(title: nil, subtitle: nil, body: "Hello")
                    ))
                },
                afterResponse: { res in
                    #expect(res.status == .forbidden)
                }
            )
        }
    }

    @Test("Messages: POST /topics/:name/messages on private topic as authenticated without permission returns 403")
    func publishToPrivateTopicAuthenticatedWithoutPermission() async throws {
        try await withApp { app in
            try await seedTopics(app)
            let session = try await login(app, username: "vi", password: "password1")
            try await app.testing().test(
                .POST, "topics/private-topic/messages",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(PublishMessageRequest(
                        priority: 3,
                        tags: nil,
                        payload: MessagePayload(title: nil, subtitle: nil, body: "Hello")
                    ))
                },
                afterResponse: { res in
                    #expect(res.status == .forbidden)
                }
            )
        }
    }

    @Test("Messages: POST /topics/:name/messages on private topic as authenticated with rw permission publishes")
    func publishToPrivateTopicAuthenticatedWithPermission() async throws {
        try await withApp { app in
            try await seedTopics(app)
            try await savePermission(app, username: "vi", accessLevel: .readWrite, topicPattern: "private-topic")
            let session = try await login(app, username: "vi", password: "password1")
            try await app.testing().test(
                .POST, "topics/private-topic/messages",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(PublishMessageRequest(
                        priority: 3,
                        tags: nil,
                        payload: MessagePayload(title: nil, subtitle: nil, body: "Hello")
                    ))
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                }
            )
        }
    }

    @Test("Messages: POST /topics/:name/messages on private topic as guest requires share token")
    func publishToPrivateTopicGuestRequiresShareToken() async throws {
        try await withApp { app in
            try await seedTopics(app)
            let raw = try await createShareToken(app, topicName: "private-topic", accessLevel: .writeOnly)
            let session = try await loginGuest(app)
            let body = PublishMessageRequest(
                priority: 3,
                tags: nil,
                payload: MessagePayload(title: nil, subtitle: nil, body: "Hello")
            )

            try await app.testing().test(
                .POST, "topics/private-topic/messages",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(body)
                },
                afterResponse: { res in
                    #expect(res.status == .forbidden)
                }
            )

            try await app.testing().test(
                .POST, "topics/private-topic/messages",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    req.headers.replaceOrAdd(name: "X-Topic-Token", value: raw)
                    try req.content.encode(body)
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                }
            )
        }
    }

    @Test("Messages: POST /topics/:name/messages on restricted topic as non-owner returns 403")
    func publishToRestrictedTopicAsNonOwner() async throws {
        try await withApp { app in
            try await seedTopics(app)
            let session = try await login(app, username: "vi", password: "password1")
            try await app.testing().test(
                .POST, "topics/restricted-topic/messages",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(PublishMessageRequest(
                        priority: 3,
                        tags: nil,
                        payload: MessagePayload(title: nil, subtitle: nil, body: "Hello")
                    ))
                },
                afterResponse: { res in
                    #expect(res.status == .forbidden)
                }
            )
        }
    }

    @Test("Messages: POST /topics/:name/messages on restricted topic as anonymous with share token publishes")
    func publishToRestrictedTopicAnonymousWithShareToken() async throws {
        try await withApp { app in
            try await seedTopics(app)
            let raw = try await createShareToken(app, topicName: "restricted-topic", accessLevel: .readWrite)
            try await app.testing().test(
                .POST, "topics/restricted-topic/messages",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-Topic-Token", value: raw)
                    try req.content.encode(PublishMessageRequest(
                        priority: 3,
                        tags: nil,
                        payload: MessagePayload(title: nil, subtitle: nil, body: "Hello")
                    ))
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                }
            )
        }
    }

    @Test("Messages: POST /topics/:name/messages on restricted topic as owner publishes")
    func publishToRestrictedTopicAsOwner() async throws {
        try await withApp { app in
            try await seedTopics(app)
            let session = try await login(app, username: "jinx", password: "hunter2")
            try await app.testing().test(
                .POST, "topics/restricted-topic/messages",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(PublishMessageRequest(
                        priority: 3,
                        tags: nil,
                        payload: MessagePayload(title: nil, subtitle: nil, body: "Owner post")
                    ))
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                }
            )
        }
    }

    @Test("Messages: GET /topics/:name/messages lists messages")
    func listMessages() async throws {
        try await withApp { app in
            try await seedTopics(app)
            let session = try await login(app, username: "jinx", password: "hunter2")
            // publish first
            try await app.testing().test(
                .POST, "topics/public-topic/messages",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(PublishMessageRequest(
                        priority: 3,
                        tags: ["swift"],
                        payload: MessagePayload(title: "Test", subtitle: nil, body: "Body")
                    ))
                },
                afterResponse: { _ in }
            )
            try await app.testing().test(
                .GET, "topics/public-topic/messages",
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let messages = try res.content.decode([MessageResponse].self)
                    #expect(messages.count == 1)
                    #expect(messages[0].tags == ["swift"])
                }
            )
        }
    }

    @Test("Messages: GET /topics/:name/messages excludes expired messages")
    func listMessagesExcludesExpiredMessages() async throws {
        try await withApp { app in
            try await seedTopics(app)

            guard let topic = try await Topic.query(on: app.db)
                .filter(\.$name == "public-topic")
                .first()
            else {
                Issue.record("Expected seeded topic")
                return
            }
            let topicID = try topic.requireID()
            let now = Date()

            try await Message(
                topicID: topicID,
                time: now.addingTimeInterval(-120),
                payload: MessagePayload(title: nil, subtitle: nil, body: "expired"),
                expiresAt: now.addingTimeInterval(-60)
            ).save(on: app.db)
            try await Message(
                topicID: topicID,
                time: now.addingTimeInterval(-30),
                payload: MessagePayload(title: nil, subtitle: nil, body: "active"),
                expiresAt: now.addingTimeInterval(60)
            ).save(on: app.db)
            try await Message(
                topicID: topicID,
                time: now,
                payload: MessagePayload(title: nil, subtitle: nil, body: "no expiry")
            ).save(on: app.db)

            try await app.testing().test(
                .GET, "topics/public-topic/messages",
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let messages = try res.content.decode([MessageResponse].self)
                    #expect(messages.map(\.payload.body) == ["no expiry", "active"])
                }
            )
        }
    }

    @Test("Messages: GET /topics/:name/messages on private topic as anonymous returns 403")
    func listMessagesOnPrivateTopicAnonymous() async throws {
        try await withApp { app in
            try await seedTopics(app)
            try await app.testing().test(
                .GET, "topics/private-topic/messages",
                afterResponse: { res in
                    #expect(res.status == .forbidden)
                }
            )
        }
    }

    @Test("Messages: GET /topics/:name/stats as admin returns topic stats")
    func topicStatsAsAdmin() async throws {
        try await withApp { app in
            try await seedTopics(app)
            try await seedDevices(app)

            guard let topic = try await Topic.query(on: app.db)
                .filter(\.$name == "public-topic")
                .first()
            else {
                Issue.record("Expected seeded topic")
                return
            }
            let topicID = try topic.requireID()

            let devices = try await Device.query(on: app.db).all()
            #expect(devices.count >= 2)

            try await DeviceSubscription(deviceId: try devices[0].requireID(), topicId: topicID).save(on: app.db)
            try await DeviceSubscription(deviceId: try devices[1].requireID(), topicId: topicID).save(on: app.db)

            let firstMessage = Message(
                topicID: topicID,
                time: Date(timeIntervalSince1970: 1_000),
                payload: MessagePayload(title: nil, subtitle: nil, body: "first")
            )
            try await firstMessage.save(on: app.db)

            let secondMessage = Message(
                topicID: topicID,
                time: Date(timeIntervalSince1970: 2_000),
                payload: MessagePayload(title: nil, subtitle: nil, body: "second")
            )
            try await secondMessage.save(on: app.db)

            try await MessageDelivery(
                messageId: try firstMessage.requireID(),
                deviceId: try devices[0].requireID(),
                status: .pending,
                retryCount: 0
            ).save(on: app.db)
            try await MessageDelivery(
                messageId: try firstMessage.requireID(),
                deviceId: try devices[1].requireID(),
                status: .ongoing,
                retryCount: 1
            ).save(on: app.db)
            try await MessageDelivery(
                messageId: try secondMessage.requireID(),
                deviceId: try devices[0].requireID(),
                status: .delivered,
                retryCount: 0
            ).save(on: app.db)
            try await MessageDelivery(
                messageId: try secondMessage.requireID(),
                deviceId: try devices[1].requireID(),
                status: .failed,
                retryCount: 3
            ).save(on: app.db)

            let adminSession = try await login(app, username: "jinx", password: "hunter2")

            try await app.testing().test(
                .GET, "topics/public-topic/stats",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: adminSession.token)
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let stats = try res.content.decode(TopicStatsResponse.self)
                    #expect(stats.subscriberCount == 2)
                    #expect(stats.messageCount == 2)
                    #expect(stats.lastMessageAt == Date(timeIntervalSince1970: 2_000))
                    #expect(stats.deliveryStats.pending == 1)
                    #expect(stats.deliveryStats.ongoing == 1)
                    #expect(stats.deliveryStats.delivered == 1)
                    #expect(stats.deliveryStats.failed == 1)
                }
            )
        }
    }

    @Test("Messages: GET /topics/:name/stats as non-admin returns 403")
    func topicStatsAsNonAdmin() async throws {
        try await withApp { app in
            try await seedTopics(app)
            let session = try await login(app, username: "vi", password: "password1")

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

    @Test("Messages: GET /topics/:name/messages on private topic as anonymous with share token returns messages")
    func listMessagesOnPrivateTopicAnonymousWithShareToken() async throws {
        try await withApp { app in
            try await seedTopics(app)
            let raw = try await createShareToken(app, topicName: "private-topic", accessLevel: .readOnly)
            try await app.testing().test(
                .GET, "topics/private-topic/messages",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-Topic-Token", value: raw)
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let messages = try res.content.decode([MessageResponse].self)
                    #expect(messages.isEmpty)
                }
            )
        }
    }

    @Test("Messages: GET /topics/:name/messages on private topic as anonymous with invalid share token returns 403")
    func listMessagesOnPrivateTopicAnonymousWithInvalidShareToken() async throws {
        try await withApp { app in
            try await seedTopics(app)
            try await app.testing().test(
                .GET, "topics/private-topic/messages",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-Topic-Token", value: "tk_bogus")
                },
                afterResponse: { res in
                    #expect(res.status == .forbidden)
                }
            )
        }
    }

    @Test("Messages: GET /topics/:name/messages on restricted topic as anonymous with share token returns messages")
    func listMessagesOnRestrictedTopicAnonymousWithShareToken() async throws {
        try await withApp { app in
            try await seedTopics(app)
            let raw = try await createShareToken(app, topicName: "restricted-topic", accessLevel: .readOnly)
            try await app.testing().test(
                .GET, "topics/restricted-topic/messages",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-Topic-Token", value: raw)
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let messages = try res.content.decode([MessageResponse].self)
                    #expect(messages.isEmpty)
                }
            )
        }
    }

    @Test("Messages: GET /topics/:name/messages on restricted topic as anonymous with invalid share token returns 403")
    func listMessagesOnRestrictedTopicAnonymousWithInvalidShareToken() async throws {
        try await withApp { app in
            try await seedTopics(app)
            try await app.testing().test(
                .GET, "topics/restricted-topic/messages",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-Topic-Token", value: "tk_bogus")
                },
                afterResponse: { res in
                    #expect(res.status == .forbidden)
                }
            )
        }
    }
}
