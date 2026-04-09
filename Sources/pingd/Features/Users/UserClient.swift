import Fluent
import Vapor
import Foundation

struct UserClient {
    let list: @Sendable () async throws -> [User]
    let get: @Sendable (UUID) async throws -> User?
    let getByUsername: @Sendable (String) async throws -> User?
    let create: @Sendable (
        _ username: String,
        _ passwordHash: String,
        _ role: UserRole
    ) async throws -> User
    let update: @Sendable (
        UUID,
        _ passwordHash: String?,
        _ role: UserRole?
    ) async throws -> User?
    let delete: @Sendable (UUID) async throws -> Void
}

extension UserClient {
    static func live(app: Application) -> Self {
        UserClient(list: {
            try await User.query(on: app.db).all()
        }, get: { id in
            try await User.find(id, on: app.db)
        }, getByUsername: { username in
            try await User
                .query(on: app.db)
                .filter(\.$username == username)
                .first()
        }, create: { username, passwordHash, role in
            let user = User(
                username: username,
                passwordHash: passwordHash,
                role: role
            )
            try await user.save(on: app.db)
            return user
        }, update: { id, passwordHash, role in
            let user = try await User.find(id, on: app.db)
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
        }, delete: { id in
            let user = try await User.find(id, on: app.db)
            guard let user else {
                return
            }
            try await user.delete(on: app.db)
        })
    }

    static func mock(
        list: @escaping @Sendable () async throws -> [User] = { [] },
        get: @escaping @Sendable (UUID) async throws -> User? = { _ in nil },
        getByUsername: @escaping @Sendable (String) async throws -> User? = { _ in nil },
        create: @escaping @Sendable (String, String, UserRole) async throws -> User = { _, _, _ in
            User(id: UUID(), username: "user1", passwordHash: "hash-xxx", role: .user)
        },
        update: @escaping @Sendable (UUID, String?, UserRole?) async throws -> User? = { _, _, _ in nil },
        delete: @escaping @Sendable (UUID) async throws -> Void = { _ in }
    ) -> Self {
        UserClient(
            list: list,
            get: get,
            getByUsername: getByUsername,
            create: create,
            update: update,
            delete: delete
        )
    }
}

extension UserClient {
    func getUserId(for username: String) async throws -> UUID {
        let user = try await getByUsername(username)
        guard let user else {
            throw UserError.notFound
        }
        return try user.requireID()
    }

    @discardableResult
    func checkAdminPermission(for user: User) throws -> Bool {
        guard user.role == .admin else {
            throw UserError.accessDenied
        }
        return true
    }

    @discardableResult
    func checkUserPermission(for user: User, targetUser: String) throws -> Bool {
        if user.role == .admin { return true }
        guard user.username == targetUser else {
            throw UserError.accessDenied
        }
        return true
    }
}
