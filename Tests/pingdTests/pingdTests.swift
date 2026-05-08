import Fluent
@testable import pingd
import Testing
import Vapor
import VaporTesting


@Suite("Pingd Tests", .serialized)
struct PingdTests {
    func withApp(_ test: (Application) async throws -> Void) async throws {
        let app = try await Application.make(.testing)
        do {
            try await configure(app)
            try await app.autoMigrate()
            try await seedUsers(app)
            try await test(app)
            try await app.autoRevert()
        } catch {
            try? await app.autoRevert()
            try await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    func seedUsers(_ app: Application) async throws {
        for user in User.allUsers {
            let fresh = User(username: user.username, passwordHash: user.passwordHash, role: user.role)
            try await fresh.save(on: app.db)
        }
    }

    func seedTopics(_ app: Application) async throws {
        guard let jinx = try await User.query(on: app.db)
            .filter(\.$username == "jinx")
            .first()
        else { return }
        let jinxID = try jinx.requireID()
        let topics: [Topic] = [
            Topic(name: "public-topic", ownerUserID: jinxID, publicRead: true, publicPublish: true),
            Topic(name: "private-topic", ownerUserID: jinxID, publicRead: false, publicPublish: false),
            Topic(name: "restricted-topic", ownerUserID: jinxID, publicRead: false, publicPublish: false),
        ]
        for topic in topics {
            try await topic.save(on: app.db)
        }
    }

    @discardableResult
    func createShareToken(
        _ app: Application,
        topicName: String,
        accessLevel: AccessLevel,
        expiresAt: Date? = nil
    ) async throws -> String {
        guard let topic = try await Topic.query(on: app.db).filter(\.$name == topicName).first()
        else {
            throw Abort(.internalServerError, reason: "Topic '\(topicName)' not seeded")
        }
        let owner = try await requireUser(app, username: "jinx")
        let (raw, hash) = TopicShareTokenCodec.generate()
        let share = TopicShareToken(
            topicID: try topic.requireID(),
            tokenHash: hash,
            label: nil,
            accessLevel: accessLevel,
            createdByUserID: try owner.requireID(),
            expiresAt: expiresAt
        )
        try await share.save(on: app.db)
        return raw
    }

    func seedDevices(_ app: Application) async throws {
        guard let vi = try await User.query(on: app.db).filter(\.$username == "vi").first(),
              let vander = try await User.query(on: app.db).filter(\.$username == "vander").first()
        else { return }
        let devices: [Device] = [
            Device(userID: try vi.requireID(), name: "Vi's iPhone", platform: .ios, pushType: .apns, pushToken: "token-vi-iphone"),
            Device(userID: try vander.requireID(), name: "Vander's Android", platform: .android, pushType: .fcm, pushToken: "token-vander-android"),
        ]
        for device in devices {
            try await device.save(on: app.db)
        }
    }

    func requireUser(_ app: Application, username: String) async throws -> User {
        try #require(
            try await User.query(on: app.db)
                .filter(\.$username == username)
                .first()
        )
    }

    func requireDeviceID(_ app: Application, username: String) async throws -> UUID {
        let user = try await requireUser(app, username: username)
        let device = try #require(
            try await Device.query(on: app.db)
                .filter(\.$user.$id == user.requireID())
                .first()
        )
        return try device.requireID()
    }

    func savePermission(
        _ app: Application,
        username: String,
        accessLevel: AccessLevel,
        topicPattern: String,
        expiresAt: Date? = nil
    ) async throws {
        let user = try await requireUser(app, username: username)
        try await Permission(
            scope: .user,
            accessLevel: accessLevel,
            userId: try user.requireID(),
            topicPattern: topicPattern,
            expiresAt: expiresAt
        ).save(on: app.db)
    }

    func saveGlobalPermission(
        _ app: Application,
        accessLevel: AccessLevel,
        topicPattern: String,
        expiresAt: Date? = nil
    ) async throws {
        try await Permission(
            scope: .global,
            accessLevel: accessLevel,
            userId: nil,
            topicPattern: topicPattern,
            expiresAt: expiresAt
        ).save(on: app.db)
    }

    func login(
        _ app: Application,
        username: String,
        password: String,
        label: String = "test"
    ) async throws -> LoginResponse {
        var result: LoginResponse?
        try await app.testing().test(
            .POST, "auth/login",
            beforeRequest: { req in
                try req.content.encode(LoginRequest(username: username, password: password, label: label))
            },
            afterResponse: { res in
                guard res.status == .ok else {
                    throw Abort(.internalServerError, reason: "Login failed: \(res.status)")
                }
                result = try res.content.decode(LoginResponse.self)
            }
        )
        return try #require(result)
    }

    func loginGuest(_ app: Application) async throws -> LoginResponse {
        var result: LoginResponse?
        try await app.testing().test(
            .POST, "auth/guest",
            afterResponse: { res in
                guard res.status == .ok else {
                    throw Abort(.internalServerError, reason: "Guest login failed: \(res.status)")
                }
                result = try res.content.decode(LoginResponse.self)
            }
        )
        return try #require(result)
    }
}
