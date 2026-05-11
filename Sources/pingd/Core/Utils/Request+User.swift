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
        if let xri = headers.first(name: "X-Real-IP")?.trimmingCharacters(in: .whitespacesAndNewlines),
           !xri.isEmpty {
            return xri
        }
        if let xff = headers.first(name: "X-Forwarded-For") {
            let ip = xff.split(separator: ",").last
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            if let ip, !ip.isEmpty {
                return ip
            }
        }
        return remoteAddress?.ipAddress ?? "unknown"
    }
}
