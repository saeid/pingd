import Vapor

enum TopicError: AbortError {
    case notFound
    case nameTaken
    case accessDenied

    var status: HTTPResponseStatus {
        switch self {
        case .notFound: .notFound
        case .nameTaken: .badRequest
        case .accessDenied: .forbidden
        }
    }

    var reason: String {
        switch self {
        case .notFound: "Topic not found"
        case .nameTaken: "Topic name already taken"
        case .accessDenied: "Access denied"
        }
    }
}

struct TopicFeature {
    /// currentUser nil = anonymous
    let listTopics: @Sendable (_ currentUser: User?) async throws -> [Topic]

    let getTopic: @Sendable (
        _ currentUser: User?,
        _ name: String,
        _ topicPassword: String?
    ) async throws -> Topic

    let createTopic: @Sendable (
        _ currentUser: User,
        _ name: String,
        _ visibility: TopicVisibility,
        _ passwordHash: String?
    ) async throws -> Topic

    let updateTopic: @Sendable (
        _ currentUser: User,
        _ name: String,
        _ visibility: TopicVisibility?,
        _ passwordHash: String??
    ) async throws -> Topic

    let deleteTopic: @Sendable (
        _ currentUser: User,
        _ name: String
    ) async throws -> Void
}

extension TopicFeature {
    static func live(topicClient: TopicClient, authClient: AuthClient) -> Self {
        TopicFeature(
            listTopics: { currentUser in
                let all = try await topicClient.list()
                if currentUser != nil {
                    // authenticated: see open + protected + private
                    return all
                } else {
                    // anonymous: only open topics
                    return all.filter { $0.visibility == .open }
                }
            },
            getTopic: { currentUser, name, topicPassword in
                guard let topic = try await topicClient.getByName(name) else {
                    throw TopicError.notFound
                }
                if try !TopicAccess.canRead(
                    topic: topic,
                    currentUser: currentUser,
                    topicPassword: topicPassword,
                    authClient: authClient
                ) {
                    throw TopicError.accessDenied
                }
                return topic
            },
            createTopic: { currentUser, name, visibility, passwordHash in
                if try await topicClient.getByName(name) != nil {
                    throw TopicError.nameTaken
                }
                let ownerID = try currentUser.requireID()
                return try await topicClient.create(name, ownerID, visibility, passwordHash)
            },
            updateTopic: { currentUser, name, visibility, passwordHash in
                guard let topic = try await topicClient.getByName(name) else {
                    throw TopicError.notFound
                }
                let topicID = try topic.requireID()
                let ownerID = topic.$owner.id
                guard try currentUser.role == .admin || (currentUser.requireID()) == ownerID else {
                    throw TopicError.accessDenied
                }
                guard let updated = try await topicClient.update(topicID, visibility, passwordHash) else {
                    throw TopicError.notFound
                }
                return updated
            },
            deleteTopic: { currentUser, name in
                guard let topic = try await topicClient.getByName(name) else {
                    throw TopicError.notFound
                }
                let topicID = try topic.requireID()
                let ownerID = topic.$owner.id
                guard try currentUser.role == .admin || (currentUser.requireID()) == ownerID else {
                    throw TopicError.accessDenied
                }
                try await topicClient.delete(topicID)
            }
        )
    }
}
