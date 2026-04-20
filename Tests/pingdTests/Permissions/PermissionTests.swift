@testable import pingd
import Testing
import VaporTesting

extension PingdTests {
    @Test("Permissions: POST /permissions/:username creates user permission as admin")
    func createPermission() async throws {
        try await withApp { app in
            let session = try await login(app, username: "jinx", password: "hunter2")
            try await app.testing().test(
                .POST, "permissions/vi",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(CreatePermissionRequest(
                        accessLevel: .readWrite,
                        topicPattern: "news.*"
                    ))
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let permission = try res.content.decode(PermissionResponse.self)
                    #expect(permission.topicPattern == "news.*")
                    #expect(permission.accessLevel == .readWrite)
                    #expect(permission.scope == .user)
                }
            )
        }
    }

    @Test("Permissions: POST /permissions/:username as non-admin returns 403")
    func createPermissionAsNonAdmin() async throws {
        try await withApp { app in
            let session = try await login(app, username: "vi", password: "password1")
            try await app.testing().test(
                .POST, "permissions/vander",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(CreatePermissionRequest(
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

    @Test("Permissions: GET /permissions/:username as admin returns list")
    func listPermissionsAsAdmin() async throws {
        try await withApp { app in
            let session = try await login(app, username: "jinx", password: "hunter2")
            try await app.testing().test(
                .POST, "permissions/vi",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(CreatePermissionRequest(
                        accessLevel: .readOnly,
                        topicPattern: "alerts.*"
                    ))
                },
                afterResponse: { _ in }
            )
            try await app.testing().test(
                .GET, "permissions/vi",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let permissions = try res.content.decode([PermissionResponse].self)
                    #expect(permissions.count == 1)
                }
            )
        }
    }

    @Test("Permissions: GET /permissions/:username as self returns list")
    func listPermissionsAsSelf() async throws {
        try await withApp { app in
            let adminSession = try await login(app, username: "jinx", password: "hunter2")
            try await app.testing().test(
                .POST, "permissions/vi",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: adminSession.token)
                    try req.content.encode(CreatePermissionRequest(
                        accessLevel: .readOnly,
                        topicPattern: "*"
                    ))
                },
                afterResponse: { _ in }
            )
            let viSession = try await login(app, username: "vi", password: "password1")
            try await app.testing().test(
                .GET, "permissions/vi",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: viSession.token)
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let permissions = try res.content.decode([PermissionResponse].self)
                    #expect(permissions.count == 1)
                }
            )
        }
    }

    @Test("Permissions: GET /permissions/:username as other non-admin returns 403")
    func listPermissionsAsOther() async throws {
        try await withApp { app in
            let session = try await login(app, username: "vander", password: "letmein")
            try await app.testing().test(
                .GET, "permissions/vi",
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
            var permissionID: UUID?
            try await app.testing().test(
                .POST, "permissions/vi",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(CreatePermissionRequest(
                        accessLevel: .readOnly,
                        topicPattern: "*"
                    ))
                },
                afterResponse: { res in
                    let permission = try res.content.decode(PermissionResponse.self)
                    permissionID = permission.id
                }
            )
            let id = try #require(permissionID)
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

    @Test("Permissions: POST /permissions creates global permission as admin")
    func createGlobalPermission() async throws {
        try await withApp { app in
            let session = try await login(app, username: "jinx", password: "hunter2")
            try await app.testing().test(
                .POST, "permissions",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(CreateGlobalPermissionRequest(
                        accessLevel: .readOnly,
                        topicPattern: "announcements.*"
                    ))
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let permission = try res.content.decode(PermissionResponse.self)
                    #expect(permission.scope == .global)
                    #expect(permission.topicPattern == "announcements.*")
                    #expect(permission.userID == nil)
                }
            )
        }
    }

    @Test("Permissions: GET /permissions lists global permissions as admin")
    func listGlobalPermissions() async throws {
        try await withApp { app in
            let session = try await login(app, username: "jinx", password: "hunter2")
            try await app.testing().test(
                .POST, "permissions",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(CreateGlobalPermissionRequest(
                        accessLevel: .readWrite,
                        topicPattern: "*"
                    ))
                },
                afterResponse: { _ in }
            )
            try await app.testing().test(
                .GET, "permissions",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let permissions = try res.content.decode([PermissionResponse].self)
                    #expect(permissions.count == 1)
                    #expect(permissions.first?.scope == .global)
                }
            )
        }
    }
}
