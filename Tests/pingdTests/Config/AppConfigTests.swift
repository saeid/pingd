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
                "PINGD_CORS_ORIGIN": "https://pingd.io, https://admin.pingd.io",
            ]
        )

        #expect(config.rateLimit.isEnabled)
        #expect(config.rateLimit.count == 12)
        #expect(config.cors.allowsAllOrigins == false)
        #expect(config.cors.explicitOrigins == ["https://pingd.io", "https://admin.pingd.io"])
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
        headers.replaceOrAdd(name: .origin, value: "https://client.pingd.io")

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
        #expect(configuration.allowedHeaders.lowercased().contains("x-topic-password"))

        try await app.asyncShutdown()
    }

    @Test("Config: CORS middleware restricts requests to explicit origins")
    func corsMiddlewareRestrictsExplicitOrigins() async throws {
        let app = try await Application.make(.testing)
        var allowedHeaders = HTTPHeaders()
        allowedHeaders.replaceOrAdd(name: .origin, value: "https://admin.pingd.io")
        var blockedHeaders = HTTPHeaders()
        blockedHeaders.replaceOrAdd(name: .origin, value: "https://other.pingd.io")

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
                explicitOrigins: ["https://admin.pingd.io"]
            )
        )

        #expect(configuration.allowedOrigin.header(forRequest: allowedRequest) == "https://admin.pingd.io")
        #expect(configuration.allowedOrigin.header(forRequest: blockedRequest).isEmpty)

        try await app.asyncShutdown()
    }
}
