import AsyncHTTPClient
import ArgumentParser

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
        ]
    )
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
