import Foundation

enum UserError: Error {
    case accessDenied
    case needAtLeastOneAdmin
    case notFound
    case userAlreadyExists
}

struct UserFeature {
    let listUsers: @Sendable (_ currentUser: User) async throws -> [User]

    let getUser: @Sendable (
        _ currentUser: User,
        _ targetUser: String
    ) async throws -> User

    let createUser: @Sendable (
        _ currentUser: User,
        _ username: String,
        _ passwordHash: String,
        _ role: UserRole?
    ) async throws -> User

    let updateUser: @Sendable (
        _ currentUser: User,
        _ targetUser: String,
        _ username: String?,
        _ role: UserRole?
    ) async throws -> User

    let deleteUser: @Sendable (
        _ currentUser: User,
        _ targetUser: String
    ) async throws -> Void
}

extension UserFeature {
    static func live(userClient: UserClient) -> Self {
        UserFeature(listUsers: { user in
            try userClient.checkAdminPermission(for: user)
            return try await userClient.list()
        }, getUser: { user, target in
            try userClient.checkUserPermission(for: user, targetUser: target)
            let userId = try await userClient.getUserId(for: target)
            guard let fetchedUser = try await userClient.get(userId) else {
                throw UserError.notFound
            }
            return fetchedUser
        }, createUser: { user, username, passwordHash, role in
            try userClient.checkAdminPermission(for: user)
            return try await userClient.create(username, passwordHash, role ?? .user)
        }, updateUser: { user, username, passwordHash, role in
            try userClient.checkAdminPermission(for: user)
            let userId = try await userClient.getUserId(for: username)
            guard let updatedUser = try await userClient.update(userId, passwordHash, role) else {
                throw UserError.notFound
            }
            return updatedUser
        }, deleteUser: { user, target in
            try userClient.checkAdminPermission(for: user)
            let userId = try await userClient.getUserId(for: target)
            try await userClient.delete(userId)
        })
    }
}
