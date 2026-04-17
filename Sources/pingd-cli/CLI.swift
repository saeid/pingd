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
        ]
    )
}
