import Vapor

struct TopicShareController: RouteCollection, @unchecked Sendable {
    let topicShareFeature: TopicShareFeature
    let auditLogger: AuditLogger

    func boot(routes: any RoutesBuilder) throws {
        let shares = routes.grouped("topics", ":name", "shares")
        shares.get(use: list)
        shares.post(use: create)
        shares.patch(":id", use: update)
        shares.post(":id", "rotate", use: rotate)
        shares.delete(":id", use: delete)
    }

    func list(_ req: Request) async throws -> [TopicShareTokenResponse] {
        guard let topicName = req.parameters.get("name") else { throw Abort(.badRequest) }
        let shares = try await topicShareFeature.listShares(req.user, topicName)
        return try shares.map { try TopicShareTokenResponse($0, rawToken: nil) }
    }

    func create(_ req: Request) async throws -> TopicShareTokenResponse {
        let currentUser = try req.user
        guard let topicName = req.parameters.get("name") else { throw Abort(.badRequest) }
        let body = try req.content.decode(CreateTopicShareRequest.self)
        do {
            let (share, raw) = try await topicShareFeature.createShare(
                currentUser,
                topicName,
                body.label,
                body.accessLevel,
                body.expiresAt
            )
            auditLogger.log("share.create", req: req, metadata: [
                "actor_username": currentUser.username,
                "actor_role": currentUser.role.rawValue,
                "topic_name": topicName,
                "share_id": share.id?.uuidString ?? "unknown",
                "access_level": share.accessLevel.rawValue,
                "ip": req.clientIP,
            ])
            return try TopicShareTokenResponse(share, rawToken: raw)
        } catch {
            auditLogger.logError("share.create", req: req, error: error, metadata: [
                "actor_username": currentUser.username,
                "topic_name": topicName,
                "ip": req.clientIP,
            ])
            throw error
        }
    }

    func rotate(_ req: Request) async throws -> TopicShareTokenResponse {
        let currentUser = try req.user
        guard let topicName = req.parameters.get("name"),
              let id = req.parameters.get("id", as: UUID.self)
        else { throw Abort(.badRequest) }
        do {
            let (share, raw) = try await topicShareFeature.rotateShare(currentUser, topicName, id)
            auditLogger.log("share.rotate", req: req, metadata: [
                "actor_username": currentUser.username,
                "topic_name": topicName,
                "share_id": id.uuidString,
                "ip": req.clientIP,
            ])
            return try TopicShareTokenResponse(share, rawToken: raw)
        } catch {
            auditLogger.logError("share.rotate", req: req, error: error, metadata: [
                "actor_username": currentUser.username,
                "topic_name": topicName,
                "share_id": id.uuidString,
                "ip": req.clientIP,
            ])
            throw error
        }
    }

    func update(_ req: Request) async throws -> TopicShareTokenResponse {
        let currentUser = try req.user
        guard let topicName = req.parameters.get("name"),
              let id = req.parameters.get("id", as: UUID.self)
        else { throw Abort(.badRequest) }
        let body = try req.content.decode(UpdateTopicShareRequest.self)
        let labelUpdate: String?? = body.labelProvided ? .some(body.label) : nil
        let expiresUpdate: Date?? = body.expiresAtProvided ? .some(body.expiresAt) : nil
        do {
            let share = try await topicShareFeature.updateShare(
                currentUser,
                topicName,
                id,
                labelUpdate,
                body.accessLevel,
                expiresUpdate
            )
            auditLogger.log("share.update", req: req, metadata: [
                "actor_username": currentUser.username,
                "topic_name": topicName,
                "share_id": id.uuidString,
                "ip": req.clientIP,
            ])
            return try TopicShareTokenResponse(share, rawToken: nil)
        } catch {
            auditLogger.logError("share.update", req: req, error: error, metadata: [
                "actor_username": currentUser.username,
                "topic_name": topicName,
                "share_id": id.uuidString,
                "ip": req.clientIP,
            ])
            throw error
        }
    }

    func delete(_ req: Request) async throws -> HTTPStatus {
        let currentUser = try req.user
        guard let topicName = req.parameters.get("name"),
              let id = req.parameters.get("id", as: UUID.self)
        else { throw Abort(.badRequest) }
        do {
            try await topicShareFeature.deleteShare(currentUser, topicName, id)
            auditLogger.log("share.delete", req: req, metadata: [
                "actor_username": currentUser.username,
                "topic_name": topicName,
                "share_id": id.uuidString,
                "ip": req.clientIP,
            ])
            return .noContent
        } catch {
            auditLogger.logError("share.delete", req: req, error: error, metadata: [
                "actor_username": currentUser.username,
                "topic_name": topicName,
                "share_id": id.uuidString,
                "ip": req.clientIP,
            ])
            throw error
        }
    }
}

// MARK: - DTOs

struct TopicShareTokenResponse: Content {
    let id: UUID
    let topicID: UUID
    let label: String?
    let accessLevel: AccessLevel
    let createdByUserID: UUID
    let expiresAt: Date?
    let createdAt: Date?
    let token: String?

    init(_ share: TopicShareToken, rawToken: String?) throws {
        id = try share.requireID()
        topicID = share.$topic.id
        label = share.label
        accessLevel = share.accessLevel
        createdByUserID = share.$createdBy.id
        expiresAt = share.expiresAt
        createdAt = share.createdAt
        token = rawToken
    }
}

struct CreateTopicShareRequest: Content {
    let label: String?
    let accessLevel: AccessLevel
    let expiresAt: Date?
}

struct UpdateTopicShareRequest: Content {
    let label: String?
    let accessLevel: AccessLevel?
    let expiresAt: Date?

    var labelProvided: Bool { _labelProvided }
    var expiresAtProvided: Bool { _expiresAtProvided }

    private let _labelProvided: Bool
    private let _expiresAtProvided: Bool

    enum CodingKeys: String, CodingKey {
        case label
        case accessLevel
        case expiresAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        _labelProvided = container.contains(.label)
        _expiresAtProvided = container.contains(.expiresAt)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        accessLevel = try container.decodeIfPresent(AccessLevel.self, forKey: .accessLevel)
        expiresAt = try container.decodeIfPresent(Date.self, forKey: .expiresAt)
    }

    init(label: String?, accessLevel: AccessLevel?, expiresAt: Date?, labelProvided: Bool, expiresAtProvided: Bool) {
        self.label = label
        self.accessLevel = accessLevel
        self.expiresAt = expiresAt
        _labelProvided = labelProvided
        _expiresAtProvided = expiresAtProvided
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if labelProvided { try container.encode(label, forKey: .label) }
        try container.encodeIfPresent(accessLevel, forKey: .accessLevel)
        if expiresAtProvided { try container.encode(expiresAt, forKey: .expiresAt) }
    }
}
