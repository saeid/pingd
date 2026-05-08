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
                .POST, "topics/public-topic/webhooks",
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

    @Test("Webhooks: non-owner without permission cannot create webhook on restricted topic")
    func createWebhookForbiddenWithoutPublishAccess() async throws {
        try await withApp { app in
            try await seedTopics(app)
            let session = try await login(app, username: "vi", password: "password1")
            try await app.testing().test(
                .POST, "topics/restricted-topic/webhooks",
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
                .POST, "topics/public-topic/webhooks",
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
                topicPattern: "restricted-topic"
            )
            try await permission.save(on: app.db)
            let session = try await login(app, username: "vi", password: "password1")
            try await app.testing().test(
                .POST, "topics/restricted-topic/webhooks",
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
                .POST, "topics/public-topic/webhooks",
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
                .GET, "topics/public-topic/messages",
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
                .POST, "topics/public-topic/webhooks",
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
                .GET, "topics/public-topic/messages",
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
                .POST, "topics/public-topic/webhooks",
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
                .POST, "topics/public-topic/webhooks",
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
                .POST, "topics/public-topic/webhooks",
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
                .DELETE, "topics/public-topic",
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

    @Test("Bool false renders as false")
    func boolFalseRendering() {
        let json: [String: Any] = ["active": false]
        #expect(WebhookTemplateRenderer.render("{{active}}", json: json) == "false")
    }

    @Test("Array value renders as empty string")
    func arrayValueRendersEmpty() {
        let json: [String: Any] = ["tags": ["a", "b"]]
        #expect(WebhookTemplateRenderer.render("[{{tags}}]", json: json) == "[]")
    }

    @Test("Object value renders as empty string")
    func objectValueRendersEmpty() {
        let json: [String: Any] = ["movie": ["title": "Dune"]]
        #expect(WebhookTemplateRenderer.render("[{{movie}}]", json: json) == "[]")
    }

    @Test("Null value renders as empty string")
    func nullValueRendersEmpty() {
        let json: [String: Any] = ["field": NSNull()]
        #expect(WebhookTemplateRenderer.render("[{{field}}]", json: json) == "[]")
    }

    @Test("Path through non-object renders as empty")
    func pathThroughScalarRendersEmpty() {
        let json: [String: Any] = ["movie": "Dune"]
        #expect(WebhookTemplateRenderer.render("{{movie.title}}", json: json) == "")
    }

    @Test("Multiple placeholders on same line all resolve")
    func multiplePlaceholdersResolve() {
        let json: [String: Any] = ["a": "x", "b": "y", "c": "z"]
        let result = WebhookTemplateRenderer.render("{{a}}-{{b}}-{{c}}", json: json)
        #expect(result == "x-y-z")
    }

    @Test("Numeric value renders without decimals when integer")
    func numericValueRenders() {
        let json: [String: Any] = ["count": 42]
        #expect(WebhookTemplateRenderer.render("{{count}}", json: json) == "42")
    }

    @Test("Template without placeholders returns input unchanged")
    func templateNoPlaceholders() {
        let result = WebhookTemplateRenderer.render("plain text", json: [String: Any]())
        #expect(result == "plain text")
    }

    @Test("splitTags returns empty array for empty string")
    func splitTagsEmpty() {
        #expect(WebhookTemplateRenderer.splitTags("") == [])
    }

    @Test("splitTags returns empty array for whitespace and commas only")
    func splitTagsWhitespaceOnly() {
        #expect(WebhookTemplateRenderer.splitTags(" , , ,") == [])
    }

    @Test("splitTags does not deduplicate")
    func splitTagsDoesNotDedupe() {
        #expect(WebhookTemplateRenderer.splitTags("a,a,b") == ["a", "a", "b"])
    }
}
