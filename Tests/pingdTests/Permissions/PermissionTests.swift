@testable import pingd
import Testing
import VaporTesting

extension PingdTests {
    @Test("Permissions: POST /users/:username/permissions creates permission as admin")
    func createPermission() async throws {
        try await withApp { app in
            let session = try await login(app, username: "jinx", password: "hunter2")
            try await app.testing().test(
                .POST, "users/vi/permissions",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(CreatePermissionRequest(
                        scope: .user,
                        accessLevel: .readWrite,
                        topicPattern: "news/*"
                    ))
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let perm = try res.content.decode(PermissionResponse.self)
                    #expect(perm.topicPattern == "news/*")
                    #expect(perm.accessLevel == .readWrite)
                }
            )
        }
    }

    @Test("Permissions: POST /users/:username/permissions as non-admin returns 403")
    func createPermissionAsNonAdmin() async throws {
        try await withApp { app in
            let session = try await login(app, username: "vi", password: "password1")
            try await app.testing().test(
                .POST, "users/vander/permissions",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(CreatePermissionRequest(
                        scope: .user,
                        accessLevel: .readOnly,
                        topicPattern: "*"
                    ))
                },
                afterResponse: { res in
                    #expect(res.status == .forbidden)
                }
            )
        }
    }

    @Test("Permissions: GET /users/:username/permissions as admin returns list")
    func listPermissionsAsAdmin() async throws {
        try await withApp { app in
            let session = try await login(app, username: "jinx", password: "hunter2")
            // create one first
            try await app.testing().test(
                .POST, "users/vi/permissions",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(CreatePermissionRequest(
                        scope: .user,
                        accessLevel: .readOnly,
                        topicPattern: "alerts/*"
                    ))
                },
                afterResponse: { _ in }
            )
            try await app.testing().test(
                .GET, "users/vi/permissions",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let perms = try res.content.decode([PermissionResponse].self)
                    #expect(perms.count == 1)
                }
            )
        }
    }

    @Test("Permissions: GET /users/:username/permissions as self returns list")
    func listPermissionsAsSelf() async throws {
        try await withApp { app in
            let adminSession = try await login(app, username: "jinx", password: "hunter2")
            try await app.testing().test(
                .POST, "users/vi/permissions",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: adminSession.token)
                    try req.content.encode(CreatePermissionRequest(
                        scope: .user,
                        accessLevel: .readOnly,
                        topicPattern: "*"
                    ))
                },
                afterResponse: { _ in }
            )
            let viSession = try await login(app, username: "vi", password: "password1")
            try await app.testing().test(
                .GET, "users/vi/permissions",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: viSession.token)
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let perms = try res.content.decode([PermissionResponse].self)
                    #expect(perms.count == 1)
                }
            )
        }
    }

    @Test("Permissions: GET /users/:username/permissions as other non-admin returns 403")
    func listPermissionsAsOther() async throws {
        try await withApp { app in
            let session = try await login(app, username: "vander", password: "letmein")
            try await app.testing().test(
                .GET, "users/vi/permissions",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                },
                afterResponse: { res in
                    #expect(res.status == .forbidden)
                }
            )
        }
    }

    @Test("Permissions: DELETE /permissions/:id as admin deletes permission")
    func deletePermission() async throws {
        try await withApp { app in
            let session = try await login(app, username: "jinx", password: "hunter2")
            var permID: UUID?
            try await app.testing().test(
                .POST, "users/vi/permissions",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(CreatePermissionRequest(
                        scope: .user,
                        accessLevel: .readOnly,
                        topicPattern: "*"
                    ))
                },
                afterResponse: { res in
                    let perm = try res.content.decode(PermissionResponse.self)
                    permID = perm.id
                }
            )
            let id = try #require(permID)
            try await app.testing().test(
                .DELETE, "permissions/\(id)",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                },
                afterResponse: { res in
                    #expect(res.status == .noContent)
                }
            )
        }
    }
}
