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
                    try req.content.encode(SubscribeRequest(topicName: "public-topic"))
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let sub = try res.content.decode(SubscriptionResponse.self)
                    #expect(sub.deviceID == id)
                    #expect(sub.topicName == "public-topic")
                    #expect(sub.topicPublicRead)
                    #expect(sub.topicPublicPublish)
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
                    try req.content.encode(SubscribeRequest(topicName: "public-topic"))
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let sub = try res.content.decode(SubscriptionResponse.self)
                    #expect(sub.topicName == "public-topic")
                }
            )
        }
    }

    @Test("Subscriptions: guest needs share token for private topic")
    func guestSubscribePrivateTopicRequiresShareToken() async throws {
        try await withApp { app in
            try await seedTopics(app)
            let raw = try await createShareToken(app, topicName: "private-topic", accessLevel: .readOnly)
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
                    try req.content.encode(SubscribeRequest(topicName: "private-topic"))
                },
                afterResponse: { res in
                    #expect(res.status == .forbidden)
                }
            )

            try await app.testing().test(
                .POST, "devices/\(id)/subscriptions",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    req.headers.replaceOrAdd(name: "X-Topic-Token", value: raw)
                    try req.content.encode(SubscribeRequest(topicName: "private-topic"))
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let sub = try res.content.decode(SubscriptionResponse.self)
                    #expect(sub.topicName == "private-topic")
                }
            )
        }
    }

    @Test("Subscriptions: non-owner cannot subscribe to restricted topic")
    func nonOwnerCannotSubscribeRestrictedTopic() async throws {
        try await withApp { app in
            try await seedTopics(app)
            try await seedDevices(app)
            let session = try await login(app, username: "vi", password: "password1")
            let deviceID = try await requireDeviceID(app, username: "vi")

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

    @Test("Subscriptions: owner can subscribe to restricted topic")
    func ownerCanSubscribeRestrictedTopic() async throws {
        try await withApp { app in
            try await seedTopics(app)
            let owner = try await requireUser(app, username: "jinx")
            let device = Device(
                userID: try owner.requireID(),
                name: "Jinx iPhone",
                platform: .ios,
                pushType: .apns,
                pushToken: "token-jinx-restricted"
            )
            try await device.save(on: app.db)

            let session = try await login(app, username: "jinx", password: "hunter2")
            let deviceID = try device.requireID()
            try await app.testing().test(
                .POST, "devices/\(deviceID)/subscriptions",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(SubscribeRequest(topicName: "restricted-topic"))
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let sub = try res.content.decode(SubscriptionResponse.self)
                    #expect(sub.topicName == "restricted-topic")
                    #expect(sub.topicPublicRead == false)
                }
            )
        }
    }

    @Test("Subscriptions: guest can subscribe to private topic with valid share token")
    func guestCanSubscribePrivateTopicWithShareToken() async throws {
        try await withApp { app in
            try await seedTopics(app)
            let raw = try await createShareToken(app, topicName: "restricted-topic", accessLevel: .readOnly)
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
                        pushToken: "guest-restricted-token"
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
                    req.headers.replaceOrAdd(name: "X-Topic-Token", value: raw)
                    try req.content.encode(SubscribeRequest(topicName: "restricted-topic"))
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let sub = try res.content.decode(SubscriptionResponse.self)
                    #expect(sub.topicName == "restricted-topic")
                }
            )
        }
    }

    @Test("Subscriptions: guest cannot subscribe to private topic with invalid share token")
    func guestCannotSubscribePrivateTopicWithInvalidShareToken() async throws {
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
                        pushToken: "guest-restricted-wrong-token"
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
                    req.headers.replaceOrAdd(name: "X-Topic-Token", value: "tk_bogus")
                    try req.content.encode(SubscribeRequest(topicName: "restricted-topic"))
                },
                afterResponse: { res in
                    #expect(res.status == .forbidden)
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
                    try req.content.encode(SubscribeRequest(topicName: "public-topic"))
                },
                afterResponse: { _ in }
            )
            // duplicate
            try await app.testing().test(
                .POST, "devices/\(id)/subscriptions",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(SubscribeRequest(topicName: "public-topic"))
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
                    try req.content.encode(SubscribeRequest(topicName: "public-topic"))
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
                    #expect(subs[0].topicName == "public-topic")
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
                    try req.content.encode(SubscribeRequest(topicName: "public-topic"))
                },
                afterResponse: { _ in }
            )
            try await app.testing().test(
                .DELETE, "devices/\(id)/subscriptions/public-topic",
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
                    try req.content.encode(SubscribeRequest(topicName: "public-topic"))
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
                    #expect(subs[0].topic.name == "public-topic")
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
                    try req.content.encode(SubscribeRequest(topicName: "public-topic"))
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
                    try req.content.encode(SubscribeRequest(topicName: "public-topic"))
                },
                afterResponse: { res in
                    #expect(res.status == .forbidden)
                }
            )
        }
    }
}
