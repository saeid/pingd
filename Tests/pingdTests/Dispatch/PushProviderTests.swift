@testable import pingd
import Foundation
import Testing

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
        #expect(relayConfig.endpointURL == URL(string: "https://pingd.io/apns/push"))
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
