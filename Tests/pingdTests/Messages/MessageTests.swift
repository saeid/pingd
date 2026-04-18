@testable import pingd
import Testing
import VaporTesting

extension PingdTests {
    @Test("Messages: POST /topics/:name/messages on open topic as anonymous publishes")
    func publishToOpenTopicAnonymous() async throws {
        try await withApp { app in
            try await seedTopics(app)
            try await app.testing().test(
                .POST, "topics/open-topic/messages",
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

    @Test("Messages: POST /topics/:name/messages on protected topic as anonymous returns 403")
    func publishToProtectedTopicAnonymous() async throws {
        try await withApp { app in
            try await seedTopics(app)
            try await app.testing().test(
                .POST, "topics/protected-topic/messages",
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

    @Test("Messages: POST /topics/:name/messages on protected topic as anonymous with password publishes")
    func publishToProtectedTopicAnonymousWithPassword() async throws {
        try await withApp { app in
            try await seedTopics(app)
            try await app.testing().test(
                .POST, "topics/protected-topic/messages",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-Topic-Password", value: protectedTopicPassword)
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

    @Test("Messages: POST /topics/:name/messages on protected topic as anonymous with wrong password returns 403")
    func publishToProtectedTopicAnonymousWithWrongPassword() async throws {
        try await withApp { app in
            try await seedTopics(app)
            try await app.testing().test(
                .POST, "topics/protected-topic/messages",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-Topic-Password", value: "wrong-password")
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

    @Test("Messages: POST /topics/:name/messages on protected topic as authenticated publishes")
    func publishToProtectedTopicAuthenticated() async throws {
        try await withApp { app in
            try await seedTopics(app)
            let session = try await login(app, username: "vi", password: "password1")
            try await app.testing().test(
                .POST, "topics/protected-topic/messages",
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

    @Test("Messages: POST /topics/:name/messages on private topic as non-owner returns 403")
    func publishToPrivateTopicAsNonOwner() async throws {
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

    @Test("Messages: POST /topics/:name/messages on private topic as anonymous with password returns 403")
    func publishToPrivateTopicAnonymousWithPassword() async throws {
        try await withApp { app in
            try await seedTopics(app)
            try await app.testing().test(
                .POST, "topics/private-topic/messages",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-Topic-Password", value: privateTopicPassword)
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

    @Test("Messages: POST /topics/:name/messages on private topic as owner publishes")
    func publishToPrivateTopicAsOwner() async throws {
        try await withApp { app in
            try await seedTopics(app)
            let session = try await login(app, username: "jinx", password: "hunter2")
            try await app.testing().test(
                .POST, "topics/private-topic/messages",
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
                .POST, "topics/open-topic/messages",
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
                .GET, "topics/open-topic/messages",
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let messages = try res.content.decode([MessageResponse].self)
                    #expect(messages.count == 1)
                    #expect(messages[0].tags == ["swift"])
                }
            )
        }
    }

    @Test("Messages: GET /topics/:name/messages on protected topic as anonymous returns 403")
    func listMessagesOnProtectedTopicAnonymous() async throws {
        try await withApp { app in
            try await seedTopics(app)
            try await app.testing().test(
                .GET, "topics/protected-topic/messages",
                afterResponse: { res in
                    #expect(res.status == .forbidden)
                }
            )
        }
    }

    @Test("Messages: GET /topics/:name/messages on protected topic as anonymous with password returns messages")
    func listMessagesOnProtectedTopicAnonymousWithPassword() async throws {
        try await withApp { app in
            try await seedTopics(app)
            try await app.testing().test(
                .GET, "topics/protected-topic/messages",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-Topic-Password", value: protectedTopicPassword)
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let messages = try res.content.decode([MessageResponse].self)
                    #expect(messages.isEmpty)
                }
            )
        }
    }

    @Test("Messages: GET /topics/:name/messages on protected topic as anonymous with wrong password returns 403")
    func listMessagesOnProtectedTopicAnonymousWithWrongPassword() async throws {
        try await withApp { app in
            try await seedTopics(app)
            try await app.testing().test(
                .GET, "topics/protected-topic/messages",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-Topic-Password", value: "wrong-password")
                },
                afterResponse: { res in
                    #expect(res.status == .forbidden)
                }
            )
        }
    }

    @Test("Messages: GET /topics/:name/messages on private topic as anonymous with password returns messages")
    func listMessagesOnPrivateTopicAnonymousWithPassword() async throws {
        try await withApp { app in
            try await seedTopics(app)
            try await app.testing().test(
                .GET, "topics/private-topic/messages",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-Topic-Password", value: privateTopicPassword)
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let messages = try res.content.decode([MessageResponse].self)
                    #expect(messages.isEmpty)
                }
            )
        }
    }

    @Test("Messages: GET /topics/:name/messages on private topic as anonymous with wrong password returns 403")
    func listMessagesOnPrivateTopicAnonymousWithWrongPassword() async throws {
        try await withApp { app in
            try await seedTopics(app)
            try await app.testing().test(
                .GET, "topics/private-topic/messages",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-Topic-Password", value: "wrong-password")
                },
                afterResponse: { res in
                    #expect(res.status == .forbidden)
                }
            )
        }
    }
}
