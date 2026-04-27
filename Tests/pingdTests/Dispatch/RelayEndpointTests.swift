@testable import pingd
import Testing
import VaporTesting

extension PingdTests {
    @Test("Relay: POST /apns/push delivers via mock provider")
    func relayPushSuccess() async throws {
        try await withApp { app in
            let adminSession = try await login(app, username: "jinx", password: "hunter2")

            let relayRequest = RelayPushRequest(
                deviceToken: "abc123",
                payload: MessagePayload(title: "Test", subtitle: nil, body: "Hello"),
                metadata: PingdAPNSPayload(
                    messageID: .init(),
                    topic: "test-topic",
                    priority: 3,
                    tags: nil,
                    time: Date()
                ),
                expiresAt: nil
            )

            try await app.testing().test(
                .POST, "apns/push",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: adminSession.token)
                    try req.content.encode(relayRequest)
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                }
            )
        }
    }

    @Test("Relay: POST /apns/push without auth returns 401")
    func relayPushUnauthorized() async throws {
        try await withApp { app in
            let relayRequest = RelayPushRequest(
                deviceToken: "abc123",
                payload: MessagePayload(title: "Test", subtitle: nil, body: "Hello"),
                metadata: PingdAPNSPayload(
                    messageID: .init(),
                    topic: "test-topic",
                    priority: 3,
                    tags: nil,
                    time: Date()
                ),
                expiresAt: nil
            )

            try await app.testing().test(
                .POST, "apns/push",
                beforeRequest: { req in
                    try req.content.encode(relayRequest)
                },
                afterResponse: { res in
                    #expect(res.status == .unauthorized)
                }
            )
        }
    }

    @Test("Relay: POST /apns/push with invalid body returns 400")
    func relayPushInvalidBody() async throws {
        try await withApp { app in
            let adminSession = try await login(app, username: "jinx", password: "hunter2")

            try await app.testing().test(
                .POST, "apns/push",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: adminSession.token)
                    try req.content.encode(["invalid": "data"])
                },
                afterResponse: { res in
                    #expect(res.status == .badRequest)
                }
            )
        }
    }
}
