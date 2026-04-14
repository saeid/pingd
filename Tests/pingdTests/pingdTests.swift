import Fluent
@testable import pingd
import Testing
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
            Topic(name: "open-topic", ownerUserID: jinxID, visibility: .open),
            Topic(name: "protected-topic", ownerUserID: jinxID, visibility: .protected),
            Topic(name: "private-topic", ownerUserID: jinxID, visibility: .private),
        ]
        for topic in topics {
            try await topic.save(on: app.db)
        }
    }

    func login(
        _ app: Application,
        username: String,
        password: String
    ) async throws -> LoginResponse {
        var result: LoginResponse?
        try await app.testing().test(
            .POST, "auth/login",
            beforeRequest: { req in
                try req.content.encode(LoginRequest(username: username, password: password, label: nil))
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
}
