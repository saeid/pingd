import Foundation
import Vapor

enum AppConfigError: LocalizedError {
    case invalidInteger(String, String)
    case invalidDuration(String, String)

    var errorDescription: String? {
        switch self {
        case let .invalidInteger(key, value):
            "Invalid integer value for \(key): \(value)"
        case let .invalidDuration(key, value):
            "Invalid duration value for \(key): \(value)"
        }
    }
}

struct AppConfig {
    let rateLimit: RateLimitConfig
    let webhookRateLimit: WebhookRateLimitConfig
    let cors: CORSConfig
    let allowRegistration: Bool
    let guestEnabled: Bool
    let reservedTopicNames: Set<String>
    let defaultPublicRead: Bool
    let defaultPublicPublish: Bool
    let defaultShareTokenTTL: TimeInterval?
    let defaultPermissionTTL: TimeInterval?
    let maxTopicsPerUser: Int?
    let maxShareTokensPerTopic: Int?
    let publishRateLimitPerUserPerMin: Int?
    let anonPublishRateLimitPerIPPerMin: Int?

    init(
        rateLimit: RateLimitConfig,
        webhookRateLimit: WebhookRateLimitConfig,
        cors: CORSConfig,
        allowRegistration: Bool,
        guestEnabled: Bool = true,
        reservedTopicNames: Set<String> = [],
        defaultPublicRead: Bool = false,
        defaultPublicPublish: Bool = false,
        defaultShareTokenTTL: TimeInterval? = nil,
        defaultPermissionTTL: TimeInterval? = nil,
        maxTopicsPerUser: Int? = nil,
        maxShareTokensPerTopic: Int? = nil,
        publishRateLimitPerUserPerMin: Int? = nil,
        anonPublishRateLimitPerIPPerMin: Int? = nil
    ) {
        self.rateLimit = rateLimit
        self.webhookRateLimit = webhookRateLimit
        self.cors = cors
        self.allowRegistration = allowRegistration
        self.guestEnabled = guestEnabled
        self.reservedTopicNames = reservedTopicNames
        self.defaultPublicRead = defaultPublicRead
        self.defaultPublicPublish = defaultPublicPublish
        self.defaultShareTokenTTL = defaultShareTokenTTL
        self.defaultPermissionTTL = defaultPermissionTTL
        self.maxTopicsPerUser = maxTopicsPerUser
        self.maxShareTokensPerTopic = maxShareTokensPerTopic
        self.publishRateLimitPerUserPerMin = publishRateLimitPerUserPerMin
        self.anonPublishRateLimitPerIPPerMin = anonPublishRateLimitPerIPPerMin
    }

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
            allowRegistration: parseBool(
                for: "PINGD_ALLOW_REGISTRATION",
                environmentVariables: environmentVariables,
                default: false
            ),
            guestEnabled: parseBool(
                for: "PINGD_GUEST_ENABLED",
                environmentVariables: environmentVariables,
                default: true
            ),
            reservedTopicNames: parseReservedTopicNames(
                for: "PINGD_RESERVED_TOPIC_NAMES",
                environmentVariables: environmentVariables
            ),
            defaultPublicRead: parseBool(
                for: "PINGD_DEFAULT_PUBLIC_READ",
                environmentVariables: environmentVariables,
                default: false
            ),
            defaultPublicPublish: parseBool(
                for: "PINGD_DEFAULT_PUBLIC_PUBLISH",
                environmentVariables: environmentVariables,
                default: false
            ),
            defaultShareTokenTTL: try parseDuration(
                for: "PINGD_DEFAULT_SHARE_TOKEN_TTL",
                environmentVariables: environmentVariables
            ),
            defaultPermissionTTL: try parseDuration(
                for: "PINGD_DEFAULT_PERMISSION_TTL",
                environmentVariables: environmentVariables
            ),
            maxTopicsPerUser: try parseOptionalPositiveInt(
                for: "PINGD_MAX_TOPICS_PER_USER",
                environmentVariables: environmentVariables
            ),
            maxShareTokensPerTopic: try parseOptionalPositiveInt(
                for: "PINGD_MAX_SHARE_TOKENS_PER_TOPIC",
                environmentVariables: environmentVariables
            ),
            publishRateLimitPerUserPerMin: try parseOptionalPositiveInt(
                for: "PINGD_PUBLISH_RATE_LIMIT_PER_USER_PER_MIN",
                environmentVariables: environmentVariables
            ),
            anonPublishRateLimitPerIPPerMin: try parseOptionalPositiveInt(
                for: "PINGD_ANON_PUBLISH_RATE_LIMIT_PER_IP_PER_MIN",
                environmentVariables: environmentVariables
            )
        )
    }

    private static func parseReservedTopicNames(
        for key: String,
        environmentVariables: [String: String]
    ) -> Set<String> {
        guard let raw = environmentVariables[key], !raw.isEmpty else {
            return []
        }
        let names = raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        return Set(names)
    }

    private static func parseBool(
        for key: String,
        environmentVariables: [String: String],
        default defaultValue: Bool
    ) -> Bool {
        guard let raw = environmentVariables[key], !raw.isEmpty else {
            return defaultValue
        }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "true"
    }

    static func parseDuration(
        for key: String,
        environmentVariables: [String: String]
    ) throws -> TimeInterval? {
        guard let raw = environmentVariables[key] else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let plainSeconds = Int(trimmed), plainSeconds > 0 {
            return TimeInterval(plainSeconds)
        }

        guard let unit = trimmed.last,
              let amount = Int(trimmed.dropLast()),
              amount > 0 else {
            throw AppConfigError.invalidDuration(key, raw)
        }

        let multiplier: Int
        switch unit {
        case "s": multiplier = 1
        case "m": multiplier = 60
        case "h": multiplier = 3600
        case "d": multiplier = 86400
        default:
            throw AppConfigError.invalidDuration(key, raw)
        }

        return TimeInterval(amount * multiplier)
    }

    private static func parseOptionalPositiveInt(
        for key: String,
        environmentVariables: [String: String]
    ) throws -> Int? {
        guard let raw = environmentVariables[key] else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let value = Int(trimmed), value > 0 else {
            throw AppConfigError.invalidInteger(key, raw)
        }
        return value
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
