import Fluent
import Vapor
import Foundation

struct TopicClient {
    let list: @Sendable () async throws -> [Topic]
    let get: @Sendable (UUID) async throws -> Topic?
    let getByName: @Sendable (String) async throws -> Topic?
    let countForOwner: @Sendable (_ ownerID: UUID) async throws -> Int
    let create: @Sendable (
        _ name: String,
        _ ownerID: UUID,
        _ publicRead: Bool,
        _ publicPublish: Bool
    ) async throws -> Topic
    let update: @Sendable (
        UUID,
        _ publicRead: Bool?,
        _ publicPublish: Bool?
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
            countForOwner: { ownerID in
                try await Topic.query(on: app.db)
                    .filter(\.$owner.$id == ownerID)
                    .count()
            },
            create: { name, ownerID, publicRead, publicPublish in
                let topic = Topic(
                    name: name,
                    ownerUserID: ownerID,
                    publicRead: publicRead,
                    publicPublish: publicPublish
                )
                try await topic.save(on: app.db)
                return topic
            },
            update: { id, publicRead, publicPublish in
                guard let topic = try await Topic.find(id, on: app.db) else {
                    return nil
                }
                if let publicRead { topic.publicRead = publicRead }
                if let publicPublish { topic.publicPublish = publicPublish }
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
        countForOwner: @escaping @Sendable (UUID) async throws -> Int = { _ in 0 },
        create: @escaping @Sendable (String, UUID, Bool, Bool) async throws -> Topic = { name, ownerID, publicRead, publicPublish in
            Topic(name: name, ownerUserID: ownerID, publicRead: publicRead, publicPublish: publicPublish)
        },
        update: @escaping @Sendable (UUID, Bool?, Bool?) async throws -> Topic? = { _, _, _ in nil },
        delete: @escaping @Sendable (UUID) async throws -> Void = { _ in }
    ) -> Self {
        TopicClient(
            list: list,
            get: get,
            getByName: getByName,
            countForOwner: countForOwner,
            create: create,
            update: update,
            delete: delete
        )
    }
}
