@testable import pingd
import Testing
import VaporTesting

extension PingdTests {
    @Test("Subscriptions: POST /devices/:id/subscriptions subscribes device to topic")
    func subscribeDevice() async throws {
        try await withApp { app in
            try await seedTopics(app)
            try await seedDevices(app)
            let session = try await login(app, username: "vi", password: "password1")
            var deviceID: UUID?
            try await app.testing().test(
                .GET, "devices",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                },
                afterResponse: { res in
                    let devices = try res.content.decode([DeviceResponse].self)
                    deviceID = devices[0].id
                }
            )
            let id = try #require(deviceID)
            try await app.testing().test(
                .POST, "devices/\(id)/subscriptions",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(SubscribeRequest(topicName: "open-topic"))
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let sub = try res.content.decode(SubscriptionResponse.self)
                    #expect(sub.deviceID == id)
                    #expect(sub.topicName == "open-topic")
                    #expect(sub.topicVisibility == "open")
                    #expect(sub.topicHasPassword == false)
                }
            )
        }
    }

    @Test("Subscriptions: guest can subscribe to open topic")
    func guestSubscribeOpenTopic() async throws {
        try await withApp { app in
            try await seedTopics(app)
            let session = try await loginGuest(app)
            var deviceID: UUID?
            try await app.testing().test(
                .POST, "devices",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(RegisterDeviceRequest(
                        name: "Guest Phone",
                        platform: .ios,
                        pushType: .apns,
                        pushToken: "guest-open-token"
                    ))
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    deviceID = try res.content.decode(DeviceResponse.self).id
                }
            )

            let id = try #require(deviceID)
            try await app.testing().test(
                .POST, "devices/\(id)/subscriptions",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(SubscribeRequest(topicName: "open-topic"))
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let sub = try res.content.decode(SubscriptionResponse.self)
                    #expect(sub.topicName == "open-topic")
                }
            )
        }
    }

    @Test("Subscriptions: guest needs password for protected topic")
    func guestSubscribeProtectedTopicRequiresPassword() async throws {
        try await withApp { app in
            try await seedTopics(app)
            let session = try await loginGuest(app)
            var deviceID: UUID?
            try await app.testing().test(
                .POST, "devices",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(RegisterDeviceRequest(
                        name: "Guest Phone",
                        platform: .ios,
                        pushType: .apns,
                        pushToken: "guest-protected-token"
                    ))
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    deviceID = try res.content.decode(DeviceResponse.self).id
                }
            )

            let id = try #require(deviceID)
            try await app.testing().test(
                .POST, "devices/\(id)/subscriptions",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(SubscribeRequest(topicName: "protected-topic"))
                },
                afterResponse: { res in
                    #expect(res.status == .forbidden)
                }
            )

            try await app.testing().test(
                .POST, "devices/\(id)/subscriptions",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    req.headers.replaceOrAdd(name: "X-Topic-Password", value: protectedTopicPassword)
                    try req.content.encode(SubscribeRequest(topicName: "protected-topic"))
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let sub = try res.content.decode(SubscriptionResponse.self)
                    #expect(sub.topicName == "protected-topic")
                }
            )
        }
    }

    @Test("Subscriptions: POST /devices/:id/subscriptions duplicate returns 409")
    func subscribeDuplicate() async throws {
        try await withApp { app in
            try await seedTopics(app)
            try await seedDevices(app)
            let session = try await login(app, username: "vi", password: "password1")
            var deviceID: UUID?
            try await app.testing().test(
                .GET, "devices",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                },
                afterResponse: { res in
                    let devices = try res.content.decode([DeviceResponse].self)
                    deviceID = devices[0].id
                }
            )
            let id = try #require(deviceID)
            // first subscribe
            try await app.testing().test(
                .POST, "devices/\(id)/subscriptions",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(SubscribeRequest(topicName: "open-topic"))
                },
                afterResponse: { _ in }
            )
            // duplicate
            try await app.testing().test(
                .POST, "devices/\(id)/subscriptions",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(SubscribeRequest(topicName: "open-topic"))
                },
                afterResponse: { res in
                    #expect(res.status == .conflict)
                }
            )
        }
    }

    @Test("Subscriptions: GET /devices/:id/subscriptions lists subscriptions")
    func listSubscriptions() async throws {
        try await withApp { app in
            try await seedTopics(app)
            try await seedDevices(app)
            let session = try await login(app, username: "vi", password: "password1")
            var deviceID: UUID?
            try await app.testing().test(
                .GET, "devices",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                },
                afterResponse: { res in
                    let devices = try res.content.decode([DeviceResponse].self)
                    deviceID = devices[0].id
                }
            )
            let id = try #require(deviceID)
            try await app.testing().test(
                .POST, "devices/\(id)/subscriptions",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(SubscribeRequest(topicName: "open-topic"))
                },
                afterResponse: { _ in }
            )
            try await app.testing().test(
                .GET, "devices/\(id)/subscriptions",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let subs = try res.content.decode([SubscriptionResponse].self)
                    #expect(subs.count == 1)
                    #expect(subs[0].topicName == "open-topic")
                }
            )
        }
    }

    @Test("Subscriptions: DELETE /devices/:id/subscriptions/:topicName unsubscribes")
    func unsubscribeDevice() async throws {
        try await withApp { app in
            try await seedTopics(app)
            try await seedDevices(app)
            let session = try await login(app, username: "vi", password: "password1")
            var deviceID: UUID?
            try await app.testing().test(
                .GET, "devices",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                },
                afterResponse: { res in
                    let devices = try res.content.decode([DeviceResponse].self)
                    deviceID = devices[0].id
                }
            )
            let id = try #require(deviceID)
            try await app.testing().test(
                .POST, "devices/\(id)/subscriptions",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(SubscribeRequest(topicName: "open-topic"))
                },
                afterResponse: { _ in }
            )
            try await app.testing().test(
                .DELETE, "devices/\(id)/subscriptions/open-topic",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                },
                afterResponse: { res in
                    #expect(res.status == .noContent)
                }
            )
        }
    }

    @Test("Subscriptions: GET /users/:username/subscriptions lists all user subscriptions")
    func listUserSubscriptions() async throws {
        try await withApp { app in
            try await seedTopics(app)
            try await seedDevices(app)
            let session = try await login(app, username: "vi", password: "password1")
            var deviceID: UUID?
            try await app.testing().test(
                .GET, "devices",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                },
                afterResponse: { res in
                    let devices = try res.content.decode([DeviceResponse].self)
                    deviceID = devices[0].id
                }
            )
            let id = try #require(deviceID)
            try await app.testing().test(
                .POST, "devices/\(id)/subscriptions",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(SubscribeRequest(topicName: "open-topic"))
                },
                afterResponse: { _ in }
            )
            try await app.testing().test(
                .GET, "users/vi/subscriptions",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let subs = try res.content.decode([UserSubscriptionResponse].self)
                    #expect(subs.count == 1)
                    #expect(subs[0].topic.name == "open-topic")
                    #expect(subs[0].device.name == "Vi's iPhone")
                    #expect(subs[0].device.platform == "ios")
                }
            )
        }
    }

    @Test("Subscriptions: GET /users/:username/subscriptions as admin lists another user")
    func listUserSubscriptionsAsAdmin() async throws {
        try await withApp { app in
            try await seedTopics(app)
            try await seedDevices(app)
            let viSession = try await login(app, username: "vi", password: "password1")
            var deviceID: UUID?
            try await app.testing().test(
                .GET, "devices",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: viSession.token)
                },
                afterResponse: { res in
                    let devices = try res.content.decode([DeviceResponse].self)
                    deviceID = devices[0].id
                }
            )
            let id = try #require(deviceID)
            try await app.testing().test(
                .POST, "devices/\(id)/subscriptions",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: viSession.token)
                    try req.content.encode(SubscribeRequest(topicName: "open-topic"))
                },
                afterResponse: { _ in }
            )
            let adminSession = try await login(app, username: "jinx", password: "hunter2")
            try await app.testing().test(
                .GET, "users/vi/subscriptions",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: adminSession.token)
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let subs = try res.content.decode([UserSubscriptionResponse].self)
                    #expect(subs.count == 1)
                }
            )
        }
    }

    @Test("Subscriptions: GET /users/:username/subscriptions as other user returns 403")
    func listUserSubscriptionsAccessDenied() async throws {
        try await withApp { app in
            try await seedTopics(app)
            try await seedDevices(app)
            let vanderSession = try await login(app, username: "vander", password: "letmein")
            try await app.testing().test(
                .GET, "users/vi/subscriptions",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: vanderSession.token)
                },
                afterResponse: { res in
                    #expect(res.status == .forbidden)
                }
            )
        }
    }

    @Test("Subscriptions: GET /users/:username/subscriptions returns empty when none")
    func listUserSubscriptionsEmpty() async throws {
        try await withApp { app in
            try await seedTopics(app)
            try await seedDevices(app)
            let session = try await login(app, username: "vi", password: "password1")
            try await app.testing().test(
                .GET, "users/vi/subscriptions",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let subs = try res.content.decode([UserSubscriptionResponse].self)
                    #expect(subs.isEmpty)
                }
            )
        }
    }

    @Test("Subscriptions: POST /devices/:id/subscriptions as non-owner returns 403")
    func subscribeAsNonOwner() async throws {
        try await withApp { app in
            try await seedTopics(app)
            try await seedDevices(app)
            let viSession = try await login(app, username: "vi", password: "password1")
            var deviceID: UUID?
            try await app.testing().test(
                .GET, "devices",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: viSession.token)
                },
                afterResponse: { res in
                    let devices = try res.content.decode([DeviceResponse].self)
                    deviceID = devices[0].id
                }
            )
            let id = try #require(deviceID)
            let vanderSession = try await login(app, username: "vander", password: "letmein")
            try await app.testing().test(
                .POST, "devices/\(id)/subscriptions",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: vanderSession.token)
                    try req.content.encode(SubscribeRequest(topicName: "open-topic"))
                },
                afterResponse: { res in
                    #expect(res.status == .forbidden)
                }
            )
        }
    }
}
