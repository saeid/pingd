@testable import pingd
import Testing
import Vapor

extension PingdTests {
    @Test("Config: production enables rate limiting and supports explicit CORS origins")
    func appConfigProduction() throws {
        let config = try AppConfig.load(
            environment: .production,
            environmentVariables: [
                "PINGD_RATE_LIMIT_COUNT": "12",
                "PINGD_CORS_ORIGIN": "https://pingd.dev, https://admin.pingd.dev",
            ]
        )

        #expect(config.rateLimit.isEnabled)
        #expect(config.rateLimit.count == 12)
        #expect(config.cors.allowsAllOrigins == false)
        #expect(config.cors.explicitOrigins == ["https://pingd.dev", "https://admin.pingd.dev"])
    }

    @Test("Config: production allows all origins by default when no CORS origin env is set")
    func appConfigProductionDefaultCORS() throws {
        let config = try AppConfig.load(environment: .production, environmentVariables: [:])

        #expect(config.rateLimit.isEnabled)
        #expect(config.cors.allowsAllOrigins)
        #expect(config.cors.explicitOrigins.isEmpty)
    }

    @Test("Config: development disables rate limiting and allows all origins by default")
    func appConfigDevelopment() throws {
        let config = try AppConfig.load(environment: .development, environmentVariables: [:])

        #expect(config.rateLimit.isEnabled == false)
        #expect(config.rateLimit.count == 30)
        #expect(config.cors.allowsAllOrigins)
        #expect(config.cors.explicitOrigins.isEmpty)
    }

    @Test("Config: CORS middleware allows all origins by default")
    func corsMiddlewareAllowsAllOrigins() async throws {
        let app = try await Application.make(.testing)
        var headers = HTTPHeaders()
        headers.replaceOrAdd(name: .origin, value: "https://client.pingd.dev")

        let request = Request(
            application: app,
            headers: headers,
            on: app.eventLoopGroup.next()
        )

        let configuration = makeCORSConfiguration(
            from: CORSConfig(allowsAllOrigins: true, explicitOrigins: [])
        )

        #expect(configuration.allowedOrigin.header(forRequest: request) == "*")
        #expect(configuration.allowedMethods == "GET, POST, PATCH, DELETE, OPTIONS")
        #expect(configuration.allowedHeaders.lowercased().contains("x-topic-token"))

        try await app.asyncShutdown()
    }

    @Test("Config: parseDuration accepts d/h/m/s suffixes and plain seconds")
    func parseDurationFormats() throws {
        let key = "PINGD_TEST_DURATION"
        func parse(_ raw: String) throws -> TimeInterval? {
            try AppConfig.parseDuration(for: key, environmentVariables: [key: raw])
        }

        #expect(try parse("30d") == TimeInterval(30 * 24 * 60 * 60))
        #expect(try parse("12h") == TimeInterval(12 * 60 * 60))
        #expect(try parse("5m") == TimeInterval(5 * 60))
        #expect(try parse("90s") == TimeInterval(90))
        #expect(try parse("3600") == TimeInterval(60 * 60))
        #expect(try AppConfig.parseDuration(for: key, environmentVariables: [:]) == nil)
        #expect(try parse("") == nil)
    }

    @Test("Config: parseDuration rejects malformed strings")
    func parseDurationInvalid() {
        let key = "PINGD_TEST_DURATION"
        func parse(_ raw: String) throws -> TimeInterval? {
            try AppConfig.parseDuration(for: key, environmentVariables: [key: raw])
        }
        #expect(throws: AppConfigError.self) { try parse("abc") }
        #expect(throws: AppConfigError.self) { try parse("30x") }
        #expect(throws: AppConfigError.self) { try parse("-5d") }
    }

    @Test("Config: loads new quota / TTL / publish-limit / guest fields")
    func appConfigLoadsNewFields() throws {
        let config = try AppConfig.load(
            environment: .production,
            environmentVariables: [
                "PINGD_GUEST_ENABLED": "false",
                "PINGD_DEFAULT_PUBLIC_READ": "true",
                "PINGD_DEFAULT_PUBLIC_PUBLISH": "true",
                "PINGD_DEFAULT_SHARE_TOKEN_TTL": "30d",
                "PINGD_DEFAULT_PERMISSION_TTL": "1h",
                "PINGD_MAX_TOPICS_PER_USER": "10",
                "PINGD_MAX_SHARE_TOKENS_PER_TOPIC": "5",
                "PINGD_PUBLISH_RATE_LIMIT_PER_USER_PER_MIN": "60",
                "PINGD_ANON_PUBLISH_RATE_LIMIT_PER_IP_PER_MIN": "20",
            ]
        )

        #expect(config.guestEnabled == false)
        #expect(config.defaultPublicRead)
        #expect(config.defaultPublicPublish)
        #expect(config.defaultShareTokenTTL == TimeInterval(30 * 24 * 60 * 60))
        #expect(config.defaultPermissionTTL == TimeInterval(60 * 60))
        #expect(config.maxTopicsPerUser == 10)
        #expect(config.maxShareTokensPerTopic == 5)
        #expect(config.publishRateLimitPerUserPerMin == 60)
        #expect(config.anonPublishRateLimitPerIPPerMin == 20)
    }

    @Test("Config: defaults for new fields when env unset")
    func appConfigNewFieldsDefaults() throws {
        let config = try AppConfig.load(environment: .development, environmentVariables: [:])

        #expect(config.guestEnabled)
        #expect(config.defaultPublicRead == false)
        #expect(config.defaultPublicPublish == false)
        #expect(config.defaultShareTokenTTL == nil)
        #expect(config.defaultPermissionTTL == nil)
        #expect(config.maxTopicsPerUser == nil)
        #expect(config.maxShareTokensPerTopic == nil)
        #expect(config.publishRateLimitPerUserPerMin == nil)
        #expect(config.anonPublishRateLimitPerIPPerMin == nil)
    }

    @Test("Config: invalid quota integer throws")
    func appConfigInvalidQuota() {
        #expect(throws: AppConfigError.self) {
            try AppConfig.load(
                environment: .development,
                environmentVariables: ["PINGD_MAX_TOPICS_PER_USER": "abc"]
            )
        }
    }

    @Test("Config: CORS middleware restricts requests to explicit origins")
    func corsMiddlewareRestrictsExplicitOrigins() async throws {
        let app = try await Application.make(.testing)
        var allowedHeaders = HTTPHeaders()
        allowedHeaders.replaceOrAdd(name: .origin, value: "https://admin.pingd.dev")
        var blockedHeaders = HTTPHeaders()
        blockedHeaders.replaceOrAdd(name: .origin, value: "https://other.pingd.dev")

        let allowedRequest = Request(
            application: app,
            headers: allowedHeaders,
            on: app.eventLoopGroup.next()
        )
        let blockedRequest = Request(
            application: app,
            headers: blockedHeaders,
            on: app.eventLoopGroup.next()
        )

        let configuration = makeCORSConfiguration(
            from: CORSConfig(
                allowsAllOrigins: false,
                explicitOrigins: ["https://admin.pingd.dev"]
            )
        )

        #expect(configuration.allowedOrigin.header(forRequest: allowedRequest) == "https://admin.pingd.dev")
        #expect(configuration.allowedOrigin.header(forRequest: blockedRequest).isEmpty)

        try await app.asyncShutdown()
    }
}
