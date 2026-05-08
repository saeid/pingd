import Vapor

struct UserStorageKey: StorageKey {
    typealias Value = User
}

extension Request {
    var topicToken: String? {
        headers.first(name: "X-Topic-Token")
    }

    var user: User {
        get throws {
            guard let user = storage[UserStorageKey.self] else {
                throw Abort(.unauthorized)
            }
            return user
        }
    }

    var optionalUser: User? {
        storage[UserStorageKey.self]
    }

    var clientIP: String {
        headers.forwarded.first?.for ?? remoteAddress?.ipAddress ?? "unknown"
    }
}
