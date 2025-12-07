import Fluent
import Vapor

struct UserClient {
    let list: @Sendable () async throws -> [User]
    let get: @Sendable (_ username: String) async throws -> User?
    let create: @Sendable (
        _ username: String,
        _ passwordHash: String,
        _ role: UserRole
    ) async throws -> User
    let update: @Sendable (
        _ username: String,
        _ passwordHash: String?,
        _ role: UserRole?
    ) async throws -> User?
    let delete: @Sendable (_ username: String) async throws -> Void
}

extension UserClient {
    static func live(app: Application) -> Self {
        UserClient(list: {
            try await User.query(on: app.db).all()
        }, get: { username in
            try await User
                .query(on: app.db)
                .filter(\.$username == username)
                .first()
        }, create: { username, passwordHash, role in
            let user = User(username: username, passwordHash: passwordHash, role: role)
            try await user.save(on: app.db)
            return user
        }, update: { username, passwordHash, role in
            let user = try await User
                .query(on: app.db)
                .filter(\.$username == username)
                .first()
            guard let user else {
                return nil
            }
            if let passwordHash {
                user.passwordHash = passwordHash
            }
            if let role {
                user.role = role
            }
            try await user.save(on: app.db)
            return user
        }, delete: { username in
            let user = try await User
                .query(on: app.db)
                .filter(\.$username == username)
                .first()
            guard let user else {
                return
            }
            try await user.delete(on: app.db)
        })
    }

    static func mock(
        list: @escaping @Sendable () async throws -> [User] = { [] },
        get: @escaping @Sendable (String) async throws -> User? = { _ in nil },
        create: @escaping @Sendable (String, String, UserRole) async throws -> User = { _, _, _ in
            User(id: UUID(), username: "user1", passwordHash: "hash-xxx", role: .user)
        },
        update: @escaping @Sendable (String, String?, UserRole?) async throws -> User? = { _, _, _ in nil },
        delete: @escaping @Sendable (String) async throws -> Void = { _ in }
    ) -> Self {
        UserClient(
            list: list,
            get: get,
            create: create,
            update: update,
            delete: delete
        )
    }
}
