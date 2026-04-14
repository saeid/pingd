import Vapor

enum UserError: AbortError {
    case accessDenied
    case needAtLeastOneAdmin
    case notFound
    case userAlreadyExists

    var status: HTTPResponseStatus {
        switch self {
        case .accessDenied: .forbidden
        case .notFound: .notFound
        case .needAtLeastOneAdmin, .userAlreadyExists: .badRequest
        }
    }

    var reason: String {
        switch self {
        case .accessDenied: "Access denied"
        case .notFound: "User not found"
        case .needAtLeastOneAdmin: "At least one admin must remain"
        case .userAlreadyExists: "Username already taken"
        }
    }
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
        _ passwordHash: String?,
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
            if try await userClient.getByUsername(username) != nil {
                throw UserError.userAlreadyExists
            }
            return try await userClient.create(username, passwordHash, role ?? .user)
        }, updateUser: { user, target, passwordHash, role in
            try userClient.checkAdminPermission(for: user)
            let userId = try await userClient.getUserId(for: target)
            guard let updatedUser = try await userClient.update(userId, passwordHash, role) else {
                throw UserError.notFound
            }
            return updatedUser
        }, deleteUser: { user, target in
            try userClient.checkAdminPermission(for: user)
            let userId = try await userClient.getUserId(for: target)
            guard let targetUser = try await userClient.get(userId) else {
                throw UserError.notFound
            }
            if targetUser.role == .admin {
                let adminCount = try await userClient.list().filter { $0.role == .admin }.count
                if adminCount <= 1 {
                    throw UserError.needAtLeastOneAdmin
                }
            }
            try await userClient.delete(userId)
        })
    }
}
