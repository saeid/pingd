@testable import pingd
import Foundation
import Testing
import Vapor
import VaporTesting

extension PingdTests {
    @Test("PushProvider: APNS direct mode loads from env")
    func pushProviderAPNSDirect() throws {
        let config = try PushProvider.loadAPNSConfiguration(
            environmentVariables: [
                "PINGD_APNS_MODE": "direct",
                "PINGD_APNS_KEY_PATH": "/run/secrets/apns.p8",
                "PINGD_APNS_KEY_ID": "ABC123",
                "PINGD_APNS_TEAM_ID": "TEAM123",
                "PINGD_APNS_BUNDLE_ID": "com.example.pingd",
                "PINGD_APNS_ENV": "development",
            ]
        )

        guard case .direct(let apnsConfig) = config else {
            Issue.record("Expected APNS direct mode")
            return
        }

        #expect(apnsConfig.keyPath == "/run/secrets/apns.p8")
        #expect(apnsConfig.keyID == "ABC123")
        #expect(apnsConfig.teamID == "TEAM123")
        #expect(apnsConfig.bundleID == "com.example.pingd")
        #expect(apnsConfig.environment == .development)
    }

    @Test("PushProvider: APNS relay mode defaults to pingd relay endpoint")
    func pushProviderAPNSRelayDefaultURL() throws {
        let config = try PushProvider.loadAPNSConfiguration(
            environmentVariables: [
                "PINGD_APNS_MODE": "relay",
                "PINGD_APNS_RELAY_TOKEN": "relay-token",
            ]
        )

        guard case .relay(let relayConfig) = config else {
            Issue.record("Expected APNS relay mode")
            return
        }

        #expect(relayConfig.baseURL == APNSRelayConfiguration.defaultBaseURL)
        #expect(relayConfig.endpointURL == URL(string: "https://pingd.dev/apns/push"))
        #expect(relayConfig.authToken == "relay-token")
    }

    @Test("PushProvider: invalid mode throws error")
    func pushProviderInvalidMode() throws {
        #expect(throws: PushProviderConfigError.self) {
            try PushProvider.loadAPNSConfiguration(
                environmentVariables: [
                    "PINGD_APNS_MODE": "fcm",
                ]
            )
        }
    }

    @Test("PushProvider: no APNS env returns no configuration")
    func pushProviderNoAPNSConfiguration() throws {
        let config = try PushProvider.loadAPNSConfiguration(environmentVariables: [:])
        #expect(config == nil)
    }

    @Test("PushProvider: Web Push configuration loads from env")
    func pushProviderWebPushConfiguration() throws {
        let rawConfig = #"{"contactInformation":"mailto:admin@example.com","expirationDuration":79200,"primaryKey":"6PSSAJiMj7uOvtE4ymNo5GWcZbT226c5KlV6c+8fx5g=","validityDuration":72000}"#
        let config = try PushProvider.loadWebPushConfiguration(
            environmentVariables: [
                "PINGD_WEBPUSH_VAPID_CONFIG": rawConfig,
            ]
        )

        #expect(config != nil)
    }

    @Test("PushProvider: no Web Push env returns no configuration")
    func pushProviderNoWebPushConfiguration() throws {
        let config = try PushProvider.loadWebPushConfiguration(environmentVariables: [:])
        #expect(config == nil)
    }

    @Test("PushProvider: invalid Web Push configuration throws error")
    func pushProviderInvalidWebPushConfiguration() throws {
        #expect(throws: PushProviderConfigError.self) {
            try PushProvider.loadWebPushConfiguration(
                environmentVariables: [
                    "PINGD_WEBPUSH_VAPID_CONFIG": "{",
                ]
            )
        }
    }

    @Test("Web Push: VAPID key endpoint returns provider key")
    func webPushVAPIDKeyEndpointReturnsProviderKey() async throws {
        let app = try await Application.make(.testing)
        do {
            try app.routes.register(collection: WebPushController(pushProvider: PushProvider(
                webPushVAPIDKey: { "test-vapid-key" },
                send: { _, _, _, _, _ in PushResult(success: true, error: nil) }
            )))

            try await app.testing().test(
                .GET,
                "webpush/vapid-key",
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let options = try res.content.decode(WebPushOptionsResponse.self)
                    #expect(options.vapid == "test-vapid-key")
                }
            )
        } catch {
            try await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    @Test("Web Push: VAPID key endpoint returns 404 when disabled")
    func webPushVAPIDKeyEndpointReturnsNotFoundWhenDisabled() async throws {
        let app = try await Application.make(.testing)
        do {
            try app.routes.register(collection: WebPushController(pushProvider: .mock(logger: app.logger)))

            try await app.testing().test(
                .GET,
                "webpush/vapid-key",
                afterResponse: { res in
                    #expect(res.status == .notFound)
                }
            )
        } catch {
            try await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    @Test("PushProvider: relay mode requires relay token")
    func pushProviderAPNSRelayRequiresToken() throws {
        #expect(throws: PushProviderConfigError.self) {
            try PushProvider.loadAPNSConfiguration(
                environmentVariables: [
                    "PINGD_APNS_MODE": "relay",
                ]
            )
        }
    }
}
