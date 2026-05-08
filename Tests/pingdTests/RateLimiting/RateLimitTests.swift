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
                .POST, "topics/public-topic/messages",
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

    @Test("RateLimit: webhook receive limit is independent of API limit")
    func webhookRateLimitIndependentOfAPI() async throws {
        try await withApp { app in
            try await seedTopics(app)
            let session = try await login(app, username: "jinx", password: "hunter2")

            var token: String?
            try await app.testing().test(
                .POST, "topics/public-topic/webhooks",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(CreateWebhookRequest(template: WebhookTemplate(body: "x")))
                },
                afterResponse: { res in
                    let response = try res.content.decode(CreateWebhookResponse.self)
                    token = response.token
                }
            )
            let webhookToken = try #require(token)

            app.appConfig = AppConfig(
                rateLimit: RateLimitConfig(isEnabled: true, count: 1),
                webhookRateLimit: WebhookRateLimitConfig(isEnabled: true, perTokenCount: 100, perIPCount: 100),
                cors: app.appConfig.cors,
                allowRegistration: false
            )

            for _ in 0..<3 {
                try await app.testing().test(
                    .POST, "hooks/\(webhookToken)",
                    beforeRequest: { req in
                        req.headers.contentType = .json
                        req.body = .init(string: "{}")
                    },
                    afterResponse: { res in
                        #expect(res.status == .accepted)
                    }
                )
            }
        }
    }

    @Test("RateLimit: webhook per-token limit triggers 429")
    func webhookPerTokenLimit() async throws {
        try await withApp { app in
            app.appConfig = AppConfig(
                rateLimit: app.appConfig.rateLimit,
                webhookRateLimit: WebhookRateLimitConfig(isEnabled: true, perTokenCount: 1, perIPCount: 100),
                cors: app.appConfig.cors,
                allowRegistration: false
            )
            try await seedTopics(app)
            let session = try await login(app, username: "jinx", password: "hunter2")
            var token: String?
            try await app.testing().test(
                .POST, "topics/public-topic/webhooks",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(CreateWebhookRequest(template: WebhookTemplate(body: "x")))
                },
                afterResponse: { res in
                    token = try res.content.decode(CreateWebhookResponse.self).token
                }
            )
            let webhookToken = try #require(token)

            try await app.testing().test(
                .POST, "hooks/\(webhookToken)",
                beforeRequest: { req in
                    req.headers.contentType = .json
                    req.body = .init(string: "{}")
                },
                afterResponse: { res in
                    #expect(res.status == .accepted)
                }
            )
            try await app.testing().test(
                .POST, "hooks/\(webhookToken)",
                beforeRequest: { req in
                    req.headers.contentType = .json
                    req.body = .init(string: "{}")
                },
                afterResponse: { res in
                    #expect(res.status == .tooManyRequests)
                    #expect(res.headers.first(name: .retryAfter) == "60")
                }
            )
        }
    }

    @Test("RateLimit: webhook per-IP limit triggers across different tokens")
    func webhookPerIPLimitAcrossTokens() async throws {
        try await withApp { app in
            app.appConfig = AppConfig(
                rateLimit: app.appConfig.rateLimit,
                webhookRateLimit: WebhookRateLimitConfig(isEnabled: true, perTokenCount: 100, perIPCount: 1),
                cors: app.appConfig.cors,
                allowRegistration: false
            )
            try await seedTopics(app)
            let session = try await login(app, username: "jinx", password: "hunter2")

            func createWebhook() async throws -> String {
                var token: String?
                try await app.testing().test(
                    .POST, "topics/public-topic/webhooks",
                    beforeRequest: { req in
                        req.headers.bearerAuthorization = .init(token: session.token)
                        try req.content.encode(CreateWebhookRequest(template: WebhookTemplate(body: "x")))
                    },
                    afterResponse: { res in
                        token = try res.content.decode(CreateWebhookResponse.self).token
                    }
                )
                return try #require(token)
            }
            let firstToken = try await createWebhook()
            let secondToken = try await createWebhook()

            try await app.testing().test(
                .POST, "hooks/\(firstToken)",
                beforeRequest: { req in
                    req.headers.contentType = .json
                    req.body = .init(string: "{}")
                },
                afterResponse: { res in
                    #expect(res.status == .accepted)
                }
            )
            try await app.testing().test(
                .POST, "hooks/\(secondToken)",
                beforeRequest: { req in
                    req.headers.contentType = .json
                    req.body = .init(string: "{}")
                },
                afterResponse: { res in
                    #expect(res.status == .tooManyRequests)
                }
            )
        }
    }

    @Test("RateLimit: webhook limit disabled lets all requests through")
    func webhookRateLimitDisabled() async throws {
        try await withApp { app in
            app.appConfig = AppConfig(
                rateLimit: app.appConfig.rateLimit,
                webhookRateLimit: WebhookRateLimitConfig(isEnabled: false, perTokenCount: 1, perIPCount: 1),
                cors: app.appConfig.cors,
                allowRegistration: false
            )
            try await seedTopics(app)
            let session = try await login(app, username: "jinx", password: "hunter2")
            var token: String?
            try await app.testing().test(
                .POST, "topics/public-topic/webhooks",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(CreateWebhookRequest(template: WebhookTemplate(body: "x")))
                },
                afterResponse: { res in
                    token = try res.content.decode(CreateWebhookResponse.self).token
                }
            )
            let webhookToken = try #require(token)

            for _ in 0..<3 {
                try await app.testing().test(
                    .POST, "hooks/\(webhookToken)",
                    beforeRequest: { req in
                        req.headers.contentType = .json
                        req.body = .init(string: "{}")
                    },
                    afterResponse: { res in
                        #expect(res.status == .accepted)
                    }
                )
            }
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
                .POST, "topics/public-topic/messages",
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
