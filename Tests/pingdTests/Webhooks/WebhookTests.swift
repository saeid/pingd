import Fluent
@testable import pingd
import Testing
import VaporTesting

extension PingdTests {
    @Test("Webhooks: admin can create a webhook for a topic")
    func createWebhookAsAdmin() async throws {
        try await withApp { app in
            try await seedTopics(app)
            let session = try await login(app, username: "jinx", password: "hunter2")
            try await app.testing().test(
                .POST, "topics/open-topic/webhooks",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(CreateWebhookRequest(template: WebhookTemplate(
                        title: "{{movie.title}}",
                        body: "{{movie.folderPath}}",
                        tags: "radarr,{{eventType}}"
                    )))
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let response = try res.content.decode(CreateWebhookResponse.self)
                    #expect(response.token.hasPrefix("whk_"))
                    #expect(response.template.title == "{{movie.title}}")
                }
            )
        }
    }

    @Test("Webhooks: non-owner without permission cannot create webhook on private topic")
    func createWebhookForbiddenWithoutPublishAccess() async throws {
        try await withApp { app in
            try await seedTopics(app)
            let session = try await login(app, username: "vi", password: "password1")
            try await app.testing().test(
                .POST, "topics/private-topic/webhooks",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(CreateWebhookRequest(template: WebhookTemplate(body: "x")))
                },
                afterResponse: { res in
                    #expect(res.status == .forbidden)
                }
            )
        }
    }

    @Test("Webhooks: non-admin without ownership cannot create webhook on open topic")
    func createWebhookForbiddenForNonOwnerOnOpenTopic() async throws {
        try await withApp { app in
            try await seedTopics(app)
            let session = try await login(app, username: "vi", password: "password1")
            try await app.testing().test(
                .POST, "topics/open-topic/webhooks",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(CreateWebhookRequest(template: WebhookTemplate(body: "x")))
                },
                afterResponse: { res in
                    #expect(res.status == .forbidden)
                }
            )
        }
    }

    @Test("Webhooks: write-only permission does not grant webhook management")
    func createWebhookForbiddenWithWritePermission() async throws {
        try await withApp { app in
            try await seedTopics(app)
            let vi = try #require(
                try await User.query(on: app.db).filter(\.$username == "vi").first()
            )
            let permission = Permission(
                scope: .user,
                accessLevel: .writeOnly,
                userId: try vi.requireID(),
                topicPattern: "private-topic"
            )
            try await permission.save(on: app.db)
            let session = try await login(app, username: "vi", password: "password1")
            try await app.testing().test(
                .POST, "topics/private-topic/webhooks",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(CreateWebhookRequest(template: WebhookTemplate(body: "x")))
                },
                afterResponse: { res in
                    #expect(res.status == .forbidden)
                }
            )
        }
    }

    @Test("Webhooks: receive renders templates and publishes message")
    func receiveRendersTemplate() async throws {
        try await withApp { app in
            try await seedTopics(app)
            let session = try await login(app, username: "jinx", password: "hunter2")
            var token: String?
            try await app.testing().test(
                .POST, "topics/open-topic/webhooks",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(CreateWebhookRequest(template: WebhookTemplate(
                        title: "Movie added: {{movie.title}} ({{movie.year}})",
                        body: "Path: {{movie.folderPath}}",
                        tags: "radarr,{{eventType}}",
                        priority: 2
                    )))
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let response = try res.content.decode(CreateWebhookResponse.self)
                    token = response.token
                }
            )
            let webhookToken = try #require(token)
            let payload = """
            {
              "eventType": "MovieAdded",
              "movie": {
                "title": "Dune",
                "year": 2021,
                "folderPath": "/movies/Dune (2021)"
              }
            }
            """
            try await app.testing().test(
                .POST, "hooks/\(webhookToken)",
                beforeRequest: { req in
                    req.headers.contentType = .json
                    req.body = .init(string: payload)
                },
                afterResponse: { res in
                    #expect(res.status == .accepted)
                }
            )
            try await app.testing().test(
                .GET, "topics/open-topic/messages",
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let messages = try res.content.decode([MessageResponse].self)
                    let latest = try #require(messages.first)
                    #expect(latest.payload.title == "Movie added: Dune (2021)")
                    #expect(latest.payload.body == "Path: /movies/Dune (2021)")
                    #expect(latest.tags == ["radarr", "MovieAdded"])
                    #expect(latest.priority == 2)
                }
            )
        }
    }

    @Test("Webhooks: missing template falls back to raw body")
    func receiveFallsBackToRawBody() async throws {
        try await withApp { app in
            try await seedTopics(app)
            let session = try await login(app, username: "jinx", password: "hunter2")
            var token: String?
            try await app.testing().test(
                .POST, "topics/open-topic/webhooks",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(CreateWebhookRequest(template: WebhookTemplate()))
                },
                afterResponse: { res in
                    let response = try res.content.decode(CreateWebhookResponse.self)
                    token = response.token
                }
            )
            let webhookToken = try #require(token)
            try await app.testing().test(
                .POST, "hooks/\(webhookToken)",
                beforeRequest: { req in
                    req.headers.contentType = .plainText
                    req.body = .init(string: "raw text body")
                },
                afterResponse: { res in
                    #expect(res.status == .accepted)
                }
            )
            try await app.testing().test(
                .GET, "topics/open-topic/messages",
                afterResponse: { res in
                    let messages = try res.content.decode([MessageResponse].self)
                    let latest = try #require(messages.first)
                    #expect(latest.payload.body == "raw text body")
                }
            )
        }
    }

    @Test("Webhooks: empty body is rejected with 400")
    func receiveEmptyBodyIs400() async throws {
        try await withApp { app in
            try await seedTopics(app)
            let session = try await login(app, username: "jinx", password: "hunter2")
            var token: String?
            try await app.testing().test(
                .POST, "topics/open-topic/webhooks",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(CreateWebhookRequest(template: WebhookTemplate(body: "x")))
                },
                afterResponse: { res in
                    let response = try res.content.decode(CreateWebhookResponse.self)
                    token = response.token
                }
            )
            let webhookToken = try #require(token)
            try await app.testing().test(
                .POST, "hooks/\(webhookToken)",
                beforeRequest: { req in
                    req.headers.contentType = .json
                },
                afterResponse: { res in
                    #expect(res.status == .badRequest)
                }
            )
        }
    }

    @Test("Webhooks: unknown token returns 404")
    func receiveUnknownTokenIs404() async throws {
        try await withApp { app in
            try await seedTopics(app)
            try await app.testing().test(
                .POST, "hooks/whk_nonexistent",
                beforeRequest: { req in
                    req.headers.contentType = .json
                    req.body = .init(string: "{}")
                },
                afterResponse: { res in
                    #expect(res.status == .notFound)
                }
            )
        }
    }

    @Test("Webhooks: deleted webhook stops accepting payloads")
    func deletedWebhookRejected() async throws {
        try await withApp { app in
            try await seedTopics(app)
            let session = try await login(app, username: "jinx", password: "hunter2")
            var webhookID: String?
            var token: String?
            try await app.testing().test(
                .POST, "topics/open-topic/webhooks",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(CreateWebhookRequest(template: WebhookTemplate(body: "x")))
                },
                afterResponse: { res in
                    let response = try res.content.decode(CreateWebhookResponse.self)
                    token = response.token
                    webhookID = response.id.uuidString
                }
            )
            let id = try #require(webhookID)
            let webhookToken = try #require(token)
            try await app.testing().test(
                .DELETE, "webhooks/\(id)",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                },
                afterResponse: { res in
                    #expect(res.status == .noContent)
                }
            )
            try await app.testing().test(
                .POST, "hooks/\(webhookToken)",
                beforeRequest: { req in
                    req.headers.contentType = .json
                    req.body = .init(string: "{}")
                },
                afterResponse: { res in
                    #expect(res.status == .notFound)
                }
            )
        }
    }

    @Test("Webhooks: cascade delete removes webhooks when topic deleted")
    func cascadeDeleteOnTopic() async throws {
        try await withApp { app in
            try await seedTopics(app)
            let session = try await login(app, username: "jinx", password: "hunter2")
            var token: String?
            try await app.testing().test(
                .POST, "topics/open-topic/webhooks",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(CreateWebhookRequest(template: WebhookTemplate(body: "x")))
                },
                afterResponse: { res in
                    let response = try res.content.decode(CreateWebhookResponse.self)
                    token = response.token
                }
            )
            let webhookToken = try #require(token)
            try await app.testing().test(
                .DELETE, "topics/open-topic",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                },
                afterResponse: { res in
                    #expect(res.status == .noContent)
                }
            )
            try await app.testing().test(
                .POST, "hooks/\(webhookToken)",
                beforeRequest: { req in
                    req.headers.contentType = .json
                    req.body = .init(string: "{}")
                },
                afterResponse: { res in
                    #expect(res.status == .notFound)
                }
            )
        }
    }
}

@Suite("WebhookTemplateRenderer")
struct WebhookTemplateRendererTests {
    @Test("Renders nested paths")
    func rendersNestedPaths() {
        let json: [String: Any] = ["movie": ["title": "Dune", "year": 2021]]
        let result = WebhookTemplateRenderer.render(
            "{{movie.title}} ({{movie.year}})",
            json: json
        )
        #expect(result == "Dune (2021)")
    }

    @Test("Missing field renders empty string")
    func missingFieldRendersEmpty() {
        let json: [String: Any] = ["movie": ["title": "Dune"]]
        let result = WebhookTemplateRenderer.render(
            "Title: {{movie.title}} Year: {{movie.year}}",
            json: json
        )
        #expect(result == "Title: Dune Year: ")
    }

    @Test("Tolerates whitespace inside delimiters")
    func tolerantToWhitespace() {
        let json: [String: Any] = ["a": "x"]
        #expect(WebhookTemplateRenderer.render("{{ a }}", json: json) == "x")
        #expect(WebhookTemplateRenderer.render("{{a}}", json: json) == "x")
    }

    @Test("Splits tags and trims whitespace")
    func splitsTags() {
        let result = WebhookTemplateRenderer.splitTags("radarr, MovieAdded ,, github")
        #expect(result == ["radarr", "MovieAdded", "github"])
    }

    @Test("Bool renders as true or false")
    func boolRendering() {
        let json: [String: Any] = ["active": true]
        let result = WebhookTemplateRenderer.render("{{active}}", json: json)
        #expect(result == "true")
    }
}
