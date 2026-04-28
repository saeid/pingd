import Foundation
import Vapor

enum AppConfigError: LocalizedError {
    case invalidInteger(String, String)

    var errorDescription: String? {
        switch self {
        case let .invalidInteger(key, value):
            "Invalid integer value for \(key): \(value)"
        }
    }
}

struct AppConfig {
    let rateLimit: RateLimitConfig
    let webhookRateLimit: WebhookRateLimitConfig
    let cors: CORSConfig
    let allowRegistration: Bool

    static func load(
        environment: Environment,
        environmentVariables: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> Self {
        return try AppConfig(
            rateLimit: .load(
                environment: environment,
                environmentVariables: environmentVariables
            ),
            webhookRateLimit: .load(
                environment: environment,
                environmentVariables: environmentVariables
            ),
            cors: .load(environmentVariables: environmentVariables),
            allowRegistration: environmentVariables["PINGD_ALLOW_REGISTRATION"]?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() == "true"
        )
    }
}

struct RateLimitConfig {
    let isEnabled: Bool
    let count: Int

    static func load(environment: Environment, environmentVariables: [String: String]) throws -> Self {
        try RateLimitConfig(
            isEnabled: environment == .production,
            count: parseLimitValue(
                for: "PINGD_RATE_LIMIT_COUNT",
                environmentVariables: environmentVariables,
                default: 30
            )
        )
    }

    private static func parseLimitValue(
        for key: String,
        environmentVariables: [String: String],
        default defaultValue: Int
    ) throws -> Int {
        guard let raw = environmentVariables[key], !raw.isEmpty else {
            return defaultValue
        }
        guard let value = Int(raw), value > 0 else {
            throw AppConfigError.invalidInteger(key, raw)
        }
        return value
    }
}

struct WebhookRateLimitConfig {
    let isEnabled: Bool
    let perTokenCount: Int
    let perIPCount: Int

    static func load(environment: Environment, environmentVariables: [String: String]) throws -> Self {
        try WebhookRateLimitConfig(
            isEnabled: environment == .production,
            perTokenCount: parseLimitValue(
                for: "PINGD_WEBHOOK_RATE_LIMIT_PER_TOKEN",
                environmentVariables: environmentVariables,
                default: 120
            ),
            perIPCount: parseLimitValue(
                for: "PINGD_WEBHOOK_RATE_LIMIT_PER_IP",
                environmentVariables: environmentVariables,
                default: 300
            )
        )
    }

    private static func parseLimitValue(
        for key: String,
        environmentVariables: [String: String],
        default defaultValue: Int
    ) throws -> Int {
        guard let raw = environmentVariables[key], !raw.isEmpty else {
            return defaultValue
        }
        guard let value = Int(raw), value > 0 else {
            throw AppConfigError.invalidInteger(key, raw)
        }
        return value
    }
}

struct CORSConfig {
    let allowsAllOrigins: Bool
    let explicitOrigins: [String]

    static func load(environmentVariables: [String: String]) -> Self {
        let configuredOrigins = parseOriginValue(
            for: "PINGD_CORS_ORIGIN",
            environmentVariables: environmentVariables,
            default: "*"
        )

        if configuredOrigins == ["*"] || configuredOrigins.isEmpty {
            return CORSConfig(
                allowsAllOrigins: true,
                explicitOrigins: []
            )
        }

        return CORSConfig(
            allowsAllOrigins: false,
            explicitOrigins: configuredOrigins
        )
    }

    private static func parseOriginValue(
        for key: String,
        environmentVariables: [String: String],
        default defaultValue: String
    ) -> [String] {
        let value = environmentVariables[key] ?? defaultValue
        return value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

private struct AppConfigStorageKey: StorageKey {
    typealias Value = AppConfig
}

extension Application {
    var appConfig: AppConfig {
        get {
            guard let config = storage[AppConfigStorageKey.self] else {
                fatalError("AppConfig accessed before being configured")
            }
            return config
        }
        set {
            storage[AppConfigStorageKey.self] = newValue
        }
    }
}
