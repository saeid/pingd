import AsyncHTTPClient
import ArgumentParser
import Foundation

@main
struct PingdCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pingd-cli",
        abstract: "Pingd server management tool",
        subcommands: [
            TopicsCommand.self,
            MessagesCommand.self,
            UsersCommand.self,
            TokensCommand.self,
            PermissionsCommand.self,
            SharesCommand.self,
            WebhooksCommand.self,
        ]
    )
}

func parseDuration(_ input: String) -> TimeInterval? {
    let pattern = /^(\d+)([dhm])$/
    guard let match = input.wholeMatch(of: pattern),
          let value = Double(match.1), value > 0 else { return nil }
    switch match.2 {
    case "d": return value * 86400
    case "h": return value * 3600
    case "m": return value * 60
    default: return nil
    }
}

func parseExpiresIn(_ raw: String?) throws -> Date? {
    guard let raw, !raw.isEmpty else { return nil }
    guard let seconds = parseDuration(raw) else {
        throw ValidationError("Invalid duration: \(raw). Use format like 30d, 12h, 5m")
    }
    return Date().addingTimeInterval(seconds)
}

func formatExpiry(_ date: Date?) -> String {
    guard let date else { return "expires=never" }
    return "expires=\(ISO8601DateFormatter().string(from: date))"
}

func withAPIClient<T>(_ operation: (APIClient) async throws -> T) async throws -> T {
    let httpClient = HTTPClient(eventLoopGroupProvider: .singleton)
    let client = APIClient(config: ConfigManager.load(), httpClient: httpClient)

    do {
        let result = try await operation(client)
        try await httpClient.shutdown()
        return result
    } catch {
        try? await httpClient.shutdown()
        throw error
    }
}
