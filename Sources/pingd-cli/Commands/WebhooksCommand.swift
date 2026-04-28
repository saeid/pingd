import ArgumentParser
import Foundation

struct WebhooksCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "webhooks",
        abstract: "Manage webhooks",
        subcommands: [List.self, Show.self, Create.self, Update.self, Delete.self]
    )

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List webhooks for a topic")

        @Option(name: .shortAndLong, help: "Topic name")
        var topic: String

        func run() async throws {
            try await withAPIClient { client in
                let webhooks = try await client.get("/topics/\(topic)/webhooks", as: [WebhookDTO].self)
                if webhooks.isEmpty {
                    print("No webhooks for '\(topic)'")
                    return
                }
                for webhook in webhooks {
                    let title = webhook.template.title ?? ""
                    let preview = title.isEmpty ? "(no title template)" : title
                    print("\(webhook.id)  \(preview)")
                }
            }
        }
    }

    struct Show: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Print template JSON for a webhook")

        @Option(name: .shortAndLong, help: "Webhook ID")
        var id: String

        func run() async throws {
            try await withAPIClient { client in
                let webhook = try await client.get("/webhooks/\(id)", as: WebhookDTO.self)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(webhook.template)
                print(String(data: data, encoding: .utf8) ?? "{}")
            }
        }
    }

    struct Create: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Create a webhook from a template JSON file")

        @Option(name: .shortAndLong, help: "Topic name")
        var topic: String

        @Option(name: [.customShort("f"), .long], help: "Template JSON file path")
        var template: String

        func run() async throws {
            let templateValue = try loadTemplate(path: template)
            try await withAPIClient { client in
                let body = WebhookTemplateRequestDTO(template: templateValue)
                let response = try await client.post(
                    "/topics/\(topic)/webhooks",
                    body: body,
                    as: CreateWebhookResponseDTO.self
                )
                print("Created webhook \(response.id)")
                print("Token (shown once): \(response.token)")
                print("URL: <server>/hooks/\(response.token)")
            }
        }
    }

    struct Update: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Update a webhook template")

        @Option(name: .shortAndLong, help: "Webhook ID")
        var id: String

        @Option(name: [.customShort("f"), .long], help: "Template JSON file path")
        var template: String

        func run() async throws {
            let templateValue = try loadTemplate(path: template)
            try await withAPIClient { client in
                let body = WebhookTemplateRequestDTO(template: templateValue)
                let webhook = try await client.patch(
                    "/webhooks/\(id)",
                    body: body,
                    as: WebhookDTO.self
                )
                print("Updated webhook \(webhook.id)")
            }
        }
    }

    struct Delete: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Delete a webhook")

        @Option(name: .shortAndLong, help: "Webhook ID")
        var id: String

        func run() async throws {
            try await withAPIClient { client in
                try await client.delete("/webhooks/\(id)")
                print("Deleted webhook \(id)")
            }
        }
    }
}

private func loadTemplate(path: String) throws -> WebhookTemplateDTO {
    let url = URL(fileURLWithPath: path)
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(WebhookTemplateDTO.self, from: data)
}
