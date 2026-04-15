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
