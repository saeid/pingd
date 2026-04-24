import APNS
import APNSCore
import AsyncHTTPClient
import Vapor
import VaporAPNS

struct PushResult {
    let success: Bool
    let error: String?
}

enum PushProviderConfigError: LocalizedError, Equatable {
    case invalidValue(String, String, String)
    case invalidURL(String, String)
    case missingRequiredValue(String)

    var errorDescription: String? {
        switch self {
        case let .invalidValue(key, value, allowed):
            "Invalid value for \(key): \(value). Allowed values: \(allowed)"
        case let .invalidURL(key, value):
            "Invalid URL value for \(key): \(value)"
        case let .missingRequiredValue(key):
            "Missing required configuration value for \(key)"
        }
    }
}

enum APNSPushEnvironment: String, CaseIterable, Equatable {
    case development
    case production
}

enum APNSPushMode: Equatable {
    case direct(APNSDirectConfiguration)
    case relay(APNSRelayConfiguration)
}

struct APNSDirectConfiguration: Equatable {
    let keyPath: String
    let keyID: String
    let teamID: String
    let bundleID: String
    let environment: APNSPushEnvironment
}

struct APNSRelayConfiguration: Equatable {
    static let defaultBaseURL = URL(string: "https://pingd.io")!

    let baseURL: URL
    let authToken: String

    var endpointURL: URL {
        baseURL.appending(path: "apns").appending(path: "push")
    }
}

struct PingdAPNSPayload: Codable, Sendable {
    let messageID: UUID
    let topic: String
    let priority: UInt8
    let tags: [String]?
    let time: Date
}

struct RelayPushRequest: Content {
    let deviceToken: String
    let payload: MessagePayload
    let metadata: PingdAPNSPayload
}

struct PushProvider {
    let send: @Sendable (
        _ deviceToken: String,
        _ pushType: PushType,
        _ payload: MessagePayload,
        _ metadata: PingdAPNSPayload
    ) async throws -> PushResult
}

extension PushProvider {
    static func loadAPNSConfiguration(
        environmentVariables: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> APNSPushMode? {
        guard let modeString = trimmedValue(for: "PINGD_APNS_MODE", environmentVariables: environmentVariables) else {
            return nil
        }

        switch modeString {
        case "direct":
            return try .direct(loadDirectAPNSConfiguration(environmentVariables: environmentVariables))
        case "relay":
            return try .relay(loadRelayAPNSConfiguration(environmentVariables: environmentVariables))
        default:
            throw PushProviderConfigError.invalidValue("PINGD_APNS_MODE", modeString, "direct, relay")
        }
    }

    static func apns(application: Application, config: APNSDirectConfiguration, logger: Logger) -> Self {
        PushProvider(
            send: { deviceToken, pushType, payload, metadata in
                guard pushType == .apns else {
                    return PushResult(success: false, error: "APNS provider cannot handle \(pushType) push type")
                }

                let containerID: APNSContainers.ID = switch config.environment {
                case .development: .development
                case .production: .production
                }

                do {
                    let client = await application.apns.client(containerID)
                    let alert = APNSAlertNotificationContent(
                        title: payload.title.map { .raw($0) },
                        subtitle: payload.subtitle.map { .raw($0) },
                        body: .raw(payload.body)
                    )
                    let notification = APNSAlertNotification(
                        alert: alert,
                        expiration: .immediately,
                        priority: .immediately,
                        topic: config.bundleID,
                        payload: metadata,
                        sound: .default
                    )
                    try await client.sendAlertNotification(notification, deviceToken: deviceToken)
                    return PushResult(success: true, error: nil)
                } catch {
                    logger.error("[PushProvider.apns] Failed to send: \(error)")
                    return PushResult(success: false, error: error.localizedDescription)
                }
            }
        )
    }

    static func relay(config: APNSRelayConfiguration, logger: Logger) -> Self {
        PushProvider(
            send: { deviceToken, pushType, payload, metadata in
                guard pushType == .apns else {
                    return PushResult(success: false, error: "Relay provider cannot handle \(pushType) push type")
                }

                var request = HTTPClientRequest(url: config.endpointURL.absoluteString)
                request.method = .POST
                request.headers.add(name: "Content-Type", value: "application/json")
                request.headers.add(name: "Authorization", value: "Bearer \(config.authToken)")

                let body = RelayPushRequest(
                    deviceToken: deviceToken,
                    payload: payload,
                    metadata: metadata
                )
                let data = try JSONEncoder().encode(body)
                request.body = .bytes(data)

                let response = try await HTTPClient.shared.execute(request, timeout: .seconds(30))

                if response.status == .ok {
                    return PushResult(success: true, error: nil)
                } else {
                    let responseBody = try? await response.body.collect(upTo: 1024 * 10)
                    let message = responseBody.map { String(buffer: $0) } ?? "HTTP \(response.status.code)"
                    logger.error("[PushProvider.relay] Failed: \(message)")
                    return PushResult(success: false, error: message)
                }
            }
        )
    }

    static func mock(logger: Logger) -> Self {
        PushProvider(
            send: { deviceToken, pushType, payload, metadata in
                logger.info("[PushProvider.mock] \(pushType) | topic=\(metadata.topic) priority=\(metadata.priority) title=\(payload.title ?? "-") body=\(payload.body)")
                return PushResult(success: true, error: nil)
            }
        )
    }
}

private func loadDirectAPNSConfiguration(
    environmentVariables: [String: String]
) throws -> APNSDirectConfiguration {
    try APNSDirectConfiguration(
        keyPath: requiredValue(for: "PINGD_APNS_KEY_PATH", environmentVariables: environmentVariables),
        keyID: requiredValue(for: "PINGD_APNS_KEY_ID", environmentVariables: environmentVariables),
        teamID: requiredValue(for: "PINGD_APNS_TEAM_ID", environmentVariables: environmentVariables),
        bundleID: requiredValue(for: "PINGD_APNS_BUNDLE_ID", environmentVariables: environmentVariables),
        environment: parseAPNSEnvironment(
            for: "PINGD_APNS_ENV",
            environmentVariables: environmentVariables
        ) ?? .production
    )
}

private func loadRelayAPNSConfiguration(
    environmentVariables: [String: String]
) throws -> APNSRelayConfiguration {
    let endpointString = trimmedValue(
        for: "PINGD_APNS_RELAY_BASE_URL",
        environmentVariables: environmentVariables
    )

    let baseURL: URL
    if let endpointString {
        guard let parsedURL = URL(string: endpointString) else {
            throw PushProviderConfigError.invalidURL("PINGD_APNS_RELAY_BASE_URL", endpointString)
        }
        baseURL = parsedURL
    } else {
        baseURL = APNSRelayConfiguration.defaultBaseURL
    }

    return try APNSRelayConfiguration(
        baseURL: baseURL,
        authToken: requiredValue(for: "PINGD_APNS_RELAY_TOKEN", environmentVariables: environmentVariables)
    )
}

private func requiredValue(
    for key: String,
    environmentVariables: [String: String]
) throws -> String {
    guard let value = trimmedValue(for: key, environmentVariables: environmentVariables) else {
        throw PushProviderConfigError.missingRequiredValue(key)
    }
    return value
}

private func trimmedValue(
    for key: String,
    environmentVariables: [String: String]
) -> String? {
    guard let rawValue = environmentVariables[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
          !rawValue.isEmpty
    else {
        return nil
    }

    return rawValue
}

private func parseAPNSEnvironment(
    for key: String,
    environmentVariables: [String: String]
) throws -> APNSPushEnvironment? {
    guard let value = trimmedValue(for: key, environmentVariables: environmentVariables) else {
        return nil
    }

    guard let environment = APNSPushEnvironment(rawValue: value) else {
        let allowed = APNSPushEnvironment.allCases.map(\.rawValue).joined(separator: ", ")
        throw PushProviderConfigError.invalidValue(key, value, allowed)
    }

    return environment
}
