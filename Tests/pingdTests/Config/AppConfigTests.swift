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
}
