import Fluent
import Vapor
import Foundation

struct TopicClient {
    let list: @Sendable () async throws -> [Topic]
    let get: @Sendable (UUID) async throws -> Topic?
    let getByName: @Sendable (String) async throws -> Topic?
    let create: @Sendable (
        _ name: String,
        _ ownerID: UUID,
        _ visibility: TopicVisibility,
        _ passwordHash: String?
    ) async throws -> Topic
    let update: @Sendable (
        UUID,
        _ visibility: TopicVisibility?,
        _ passwordHash: String??
    ) async throws -> Topic?
    let delete: @Sendable (UUID) async throws -> Void
}

extension TopicClient {
    static func live(app: Application) -> Self {
        TopicClient(
            list: {
                try await Topic.query(on: app.db).all()
            },
            get: { id in
                try await Topic.find(id, on: app.db)
            },
            getByName: { name in
                try await Topic.query(on: app.db)
                    .filter(\.$name == name)
                    .first()
            },
            create: { name, ownerID, visibility, passwordHash in
                let topic = Topic(
                    name: name,
                    ownerUserID: ownerID,
                    visibility: visibility,
                    passwordHash: passwordHash
                )
                try await topic.save(on: app.db)
                return topic
            },
            update: { id, visibility, passwordHash in
                guard let topic = try await Topic.find(id, on: app.db) else {
                    return nil
                }
                if let visibility { topic.visibility = visibility }
                if let passwordHash { topic.passwordHash = passwordHash }
                try await topic.save(on: app.db)
                return topic
            },
            delete: { id in
                guard let topic = try await Topic.find(id, on: app.db) else { return }
                try await topic.delete(on: app.db)
            }
        )
    }

    static func mock(
        list: @escaping @Sendable () async throws -> [Topic] = { [] },
        get: @escaping @Sendable (UUID) async throws -> Topic? = { _ in nil },
        getByName: @escaping @Sendable (String) async throws -> Topic? = { _ in nil },
        create: @escaping @Sendable (String, UUID, TopicVisibility, String?) async throws -> Topic = { name, ownerID, visibility, _ in
            Topic(name: name, ownerUserID: ownerID, visibility: visibility)
        },
        update: @escaping @Sendable (UUID, TopicVisibility?, String??) async throws -> Topic? = { _, _, _ in nil },
        delete: @escaping @Sendable (UUID) async throws -> Void = { _ in }
    ) -> Self {
        TopicClient(list: list, get: get, getByName: getByName, create: create, update: update, delete: delete)
    }
}
