import Vapor

struct UserStorageKey: StorageKey {
    typealias Value = User
}

extension Request {
    var user: User {
        get throws {
            guard let user = storage[UserStorageKey.self] else {
                throw Abort(.unauthorized)
            }
            return user
        }
    }
}
