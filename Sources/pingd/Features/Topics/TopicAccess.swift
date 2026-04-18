import Vapor

/// `open` allows anonymous read and publish.
/// `protected` allows authenticated access or anonymous access with a matching topic password.
/// `private` allows authenticated read or anonymous read with a matching topic password, but publish stays owner/admin only.
enum TopicAccess {
    static func canRead(
        topic: Topic,
        currentUser: User?,
        topicPassword: String?,
        authClient: AuthClient
    ) throws -> Bool {
        switch topic.visibility {
        case .open:
            return true
        case .protected, .private:
            if currentUser != nil {
                return true
            }
            return try hasMatchingPassword(topic: topic, topicPassword: topicPassword, authClient: authClient)
        }
    }

    static func canPublish(
        topic: Topic,
        currentUser: User?,
        topicPassword: String?,
        authClient: AuthClient
    ) throws -> Bool {
        switch topic.visibility {
        case .open:
            return true
        case .protected:
            if currentUser != nil {
                return true
            }
            return try hasMatchingPassword(topic: topic, topicPassword: topicPassword, authClient: authClient)
        case .private:
            guard let user = currentUser else {
                return false
            }
            let ownerID = topic.$owner.id
            let userID = try user.requireID()
            return user.role == .admin || userID == ownerID
        }
    }

    private static func hasMatchingPassword(
        topic: Topic,
        topicPassword: String?,
        authClient: AuthClient
    ) throws -> Bool {
        guard let topicPassword, !topicPassword.isEmpty else {
            return false
        }
        guard let passwordHash = topic.passwordHash else {
            return false
        }
        return try authClient.verifyPassword(topicPassword, passwordHash)
    }
}
