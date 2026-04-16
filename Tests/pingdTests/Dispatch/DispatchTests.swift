@testable import pingd
import Testing
import VaporTesting

extension PingdTests {
    @Test("Dispatch: Publishing creates deliveries for subscribed devices")
    func publishCreatesDeliveries() async throws {
        try await withApp { app in
            try await seedTopics(app)
            try await seedDevices(app)
            let viSession = try await login(app, username: "vi", password: "password1")

            // get vi's device ID
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

            // subscribe vi's device to open-topic
            try await app.testing().test(
                .POST, "devices/\(id)/subscriptions",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: viSession.token)
                    try req.content.encode(SubscribeRequest(topicName: "open-topic"))
                },
                afterResponse: { _ in }
            )

            // publish message
            var messageID: UUID?
            try await app.testing().test(
                .POST, "topics/open-topic/messages",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: viSession.token)
                    try req.content.encode(PublishMessageRequest(
                        priority: 3,
                        tags: nil,
                        payload: MessagePayload(title: "Test", subtitle: nil, body: "Hello")
                    ))
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let message = try res.content.decode(MessageResponse.self)
                    messageID = message.id
                }
            )
            let msgID = try #require(messageID)

            // check deliveries
            try await app.testing().test(
                .GET, "messages/\(msgID)/deliveries",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: viSession.token)
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let deliveries = try res.content.decode([DeliveryResponse].self)
                    #expect(deliveries.count == 1)
                    #expect(deliveries[0].deviceID == id)
                    #expect(deliveries[0].status == .pending)
                }
            )
        }
    }

    @Test("Dispatch: No deliveries created when no subscriptions exist")
    func publishNoSubscriptions() async throws {
        try await withApp { app in
            try await seedTopics(app)
            let session = try await login(app, username: "jinx", password: "hunter2")

            var messageID: UUID?
            try await app.testing().test(
                .POST, "topics/open-topic/messages",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(PublishMessageRequest(
                        priority: 3,
                        tags: nil,
                        payload: MessagePayload(title: nil, subtitle: nil, body: "No subs")
                    ))
                },
                afterResponse: { res in
                    let message = try res.content.decode(MessageResponse.self)
                    messageID = message.id
                }
            )
            let msgID = try #require(messageID)

            try await app.testing().test(
                .GET, "messages/\(msgID)/deliveries",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let deliveries = try res.content.decode([DeliveryResponse].self)
                    #expect(deliveries.isEmpty)
                }
            )
        }
    }

    @Test("Dispatch: Multiple subscribed devices get deliveries")
    func publishMultipleDevices() async throws {
        try await withApp { app in
            try await seedTopics(app)
            try await seedDevices(app)
            let viSession = try await login(app, username: "vi", password: "password1")
            let vanderSession = try await login(app, username: "vander", password: "letmein")

            // get both device IDs
            var viDeviceID: UUID?
            try await app.testing().test(
                .GET, "devices",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: viSession.token)
                },
                afterResponse: { res in
                    let devices = try res.content.decode([DeviceResponse].self)
                    viDeviceID = devices[0].id
                }
            )
            var vanderDeviceID: UUID?
            try await app.testing().test(
                .GET, "devices",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: vanderSession.token)
                },
                afterResponse: { res in
                    let devices = try res.content.decode([DeviceResponse].self)
                    vanderDeviceID = devices[0].id
                }
            )

            let viID = try #require(viDeviceID)
            let vanderID = try #require(vanderDeviceID)

            // subscribe both to open-topic
            for (id, session) in [(viID, viSession), (vanderID, vanderSession)] {
                try await app.testing().test(
                    .POST, "devices/\(id)/subscriptions",
                    beforeRequest: { req in
                        req.headers.bearerAuthorization = .init(token: session.token)
                        try req.content.encode(SubscribeRequest(topicName: "open-topic"))
                    },
                    afterResponse: { _ in }
                )
            }

            // publish
            var messageID: UUID?
            try await app.testing().test(
                .POST, "topics/open-topic/messages",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: viSession.token)
                    try req.content.encode(PublishMessageRequest(
                        priority: 3,
                        tags: nil,
                        payload: MessagePayload(title: nil, subtitle: nil, body: "Multi")
                    ))
                },
                afterResponse: { res in
                    let message = try res.content.decode(MessageResponse.self)
                    messageID = message.id
                }
            )
            let msgID = try #require(messageID)

            // check 2 deliveries
            try await app.testing().test(
                .GET, "messages/\(msgID)/deliveries",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: viSession.token)
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let deliveries = try res.content.decode([DeliveryResponse].self)
                    #expect(deliveries.count == 2)
                }
            )
        }
    }
}
