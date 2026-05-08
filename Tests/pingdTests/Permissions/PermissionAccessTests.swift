@testable import pingd
import Testing
import VaporTesting

extension PingdTests {
    @Test("Permissions: read-only permission grants restricted read and subscribe but not publish")
    func readOnlyPermissionAccessOnRestrictedTopic() async throws {
        try await withApp { app in
            try await seedTopics(app)
            try await seedDevices(app)
            try await savePermission(app, username: "vi", accessLevel: .readOnly, topicPattern: "restricted-topic")

            let session = try await login(app, username: "vi", password: "password1")
            let deviceID = try await requireDeviceID(app, username: "vi")

            try await app.testing().test(
                .GET, "topics/restricted-topic",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                }
            )

            try await app.testing().test(
                .POST, "topics/restricted-topic/messages",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(PublishMessageRequest(
                        priority: 3,
                        tags: nil,
                        payload: MessagePayload(title: nil, subtitle: nil, body: "Should fail")
                    ))
                },
                afterResponse: { res in
                    #expect(res.status == .forbidden)
                }
            )

            try await app.testing().test(
                .POST, "devices/\(deviceID)/subscriptions",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(SubscribeRequest(topicName: "restricted-topic"))
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                }
            )
        }
    }

    @Test("Permissions: write-only permission grants restricted publish but not read or subscribe")
    func writeOnlyPermissionAccessOnRestrictedTopic() async throws {
        try await withApp { app in
            try await seedTopics(app)
            try await seedDevices(app)
            try await savePermission(app, username: "vi", accessLevel: .writeOnly, topicPattern: "restricted-topic")

            let session = try await login(app, username: "vi", password: "password1")
            let deviceID = try await requireDeviceID(app, username: "vi")

            try await app.testing().test(
                .GET, "topics/restricted-topic",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                },
                afterResponse: { res in
                    #expect(res.status == .forbidden)
                }
            )

            try await app.testing().test(
                .GET, "topics/restricted-topic/messages",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                },
                afterResponse: { res in
                    #expect(res.status == .forbidden)
                }
            )

            try await app.testing().test(
                .POST, "topics/restricted-topic/messages",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(PublishMessageRequest(
                        priority: 3,
                        tags: nil,
                        payload: MessagePayload(title: nil, subtitle: nil, body: "Write-only publish")
                    ))
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                }
            )

            try await app.testing().test(
                .POST, "devices/\(deviceID)/subscriptions",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(SubscribeRequest(topicName: "restricted-topic"))
                },
                afterResponse: { res in
                    #expect(res.status == .forbidden)
                }
            )
        }
    }

    @Test("Permissions: read-write permission grants restricted read publish and subscribe")
    func readWritePermissionAccessOnRestrictedTopic() async throws {
        try await withApp { app in
            try await seedTopics(app)
            try await seedDevices(app)
            try await savePermission(app, username: "vi", accessLevel: .readWrite, topicPattern: "restricted-topic")

            let session = try await login(app, username: "vi", password: "password1")
            let deviceID = try await requireDeviceID(app, username: "vi")

            try await app.testing().test(
                .GET, "topics/restricted-topic",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                }
            )

            try await app.testing().test(
                .POST, "topics/restricted-topic/messages",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(PublishMessageRequest(
                        priority: 3,
                        tags: nil,
                        payload: MessagePayload(title: nil, subtitle: nil, body: "Read-write publish")
                    ))
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                }
            )

            try await app.testing().test(
                .POST, "devices/\(deviceID)/subscriptions",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(SubscribeRequest(topicName: "restricted-topic"))
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                }
            )
        }
    }

    @Test("Permissions: global read-only permission grants restricted read and subscribe")
    func globalReadOnlyPermissionAccessOnRestrictedTopic() async throws {
        try await withApp { app in
            try await seedTopics(app)
            try await seedDevices(app)
            try await saveGlobalPermission(app, accessLevel: .readOnly, topicPattern: "restricted-topic")

            let session = try await login(app, username: "vi", password: "password1")
            let deviceID = try await requireDeviceID(app, username: "vi")

            try await app.testing().test(
                .GET, "topics/restricted-topic",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                }
            )

            try await app.testing().test(
                .POST, "topics/restricted-topic/messages",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(PublishMessageRequest(
                        priority: 3,
                        tags: nil,
                        payload: MessagePayload(title: nil, subtitle: nil, body: "Should fail")
                    ))
                },
                afterResponse: { res in
                    #expect(res.status == .forbidden)
                }
            )

            try await app.testing().test(
                .POST, "devices/\(deviceID)/subscriptions",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(SubscribeRequest(topicName: "restricted-topic"))
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                }
            )
        }
    }
}
