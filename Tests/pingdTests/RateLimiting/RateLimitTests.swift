@testable import pingd
import Testing
import Vapor
import VaporTesting

extension PingdTests {
    @Test("RateLimit: all requests share the same rate limit")
    func globalRateLimit() async throws {
        try await withApp { app in
            app.appConfig = AppConfig(
                rateLimit: RateLimitConfig(
                    isEnabled: true,
                    count: 1
                ),
                webhookRateLimit: app.appConfig.webhookRateLimit,
                cors: app.appConfig.cors,
                allowRegistration: false
            )

            try await app.testing().test(
                .GET, "health",
                beforeRequest: { _ in },
                afterResponse: { res in
                    #expect(res.status == .ok)
                }
            )

            try await app.testing().test(
                .GET, "health",
                beforeRequest: { _ in },
                afterResponse: { res in
                    #expect(res.status == .tooManyRequests)
                    #expect(res.headers.first(name: .retryAfter) == "60")
                }
            )
        }
    }

    @Test("RateLimit: different API endpoints share the same rate limit")
    func sharedRateLimitAcrossEndpoints() async throws {
        try await withApp { app in
            app.appConfig = AppConfig(
                rateLimit: RateLimitConfig(
                    isEnabled: true,
                    count: 1
                ),
                webhookRateLimit: app.appConfig.webhookRateLimit,
                cors: app.appConfig.cors,
                allowRegistration: false
            )

            try await seedTopics(app)
            let login = try await login(app, username: "jinx", password: "hunter2")

            try await app.testing().test(
                .POST, "topics/open-topic/messages",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = BearerAuthorization(token: login.token)
                    try req.content.encode(
                        PublishMessageRequest(
                            priority: 3,
                            tags: nil,
                            payload: MessagePayload(title: "One", subtitle: nil, body: "First")
                        )
                    )
                },
                afterResponse: { res in
                    #expect(res.status == .tooManyRequests)
                    #expect(res.headers.first(name: .retryAfter) == "60")
                }
            )
        }
    }

    @Test("RateLimit: authenticated requests are still rate limited")
    func authenticatedRateLimit() async throws {
        try await withApp { app in
            app.appConfig = AppConfig(
                rateLimit: RateLimitConfig(
                    isEnabled: true,
                    count: 2
                ),
                webhookRateLimit: app.appConfig.webhookRateLimit,
                cors: app.appConfig.cors,
                allowRegistration: false
            )

            try await seedTopics(app)

            try await app.testing().test(
                .GET, "health",
                beforeRequest: { _ in },
                afterResponse: { res in
                    #expect(res.status == .ok)
                }
            )

            let login = try await login(app, username: "jinx", password: "hunter2")

            try await app.testing().test(
                .POST, "topics/open-topic/messages",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = BearerAuthorization(token: login.token)
                    try req.content.encode(
                        PublishMessageRequest(
                            priority: 3,
                            tags: nil,
                            payload: MessagePayload(title: "Two", subtitle: nil, body: "Second")
                        )
                    )
                },
                afterResponse: { res in
                    #expect(res.status == .tooManyRequests)
                    #expect(res.headers.first(name: .retryAfter) == "60")
                }
            )
        }
    }
}
