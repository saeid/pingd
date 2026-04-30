import Vapor

struct DeviceController: RouteCollection, @unchecked Sendable {
    let deviceFeature: DeviceFeature
    let auditLogger: AuditLogger

    func boot(routes: any RoutesBuilder) throws {
        let devices = routes.grouped("devices")
        devices.get(use: list)
        devices.post(use: register)
        devices.patch(":id", use: update)
        devices.delete(":id", use: delete)
    }

    func list(_ req: Request) async throws -> [DeviceResponse] {
        let devices = try await deviceFeature.listDevices(try req.user)
        return try devices.map(DeviceResponse.init)
    }

    func register(_ req: Request) async throws -> DeviceResponse {
        let currentUser = try req.user
        try RegisterDeviceRequest.validate(content: req)
        let body = try req.content.decode(RegisterDeviceRequest.self)
        do {
            let device = try await deviceFeature.registerDevice(
                currentUser,
                body.name,
                body.platform,
                body.pushType,
                body.pushToken,
                body.deliveryEnabled ?? true
            )
            auditLogger.log("device.register", req: req, metadata: [
                "actor_username": currentUser.username,
                "device_name": body.name,
                "platform": body.platform.rawValue,
                "ip": req.clientIP,
            ])
            return try DeviceResponse(device)
        } catch {
            auditLogger.logError("device.register", req: req, error: error, metadata: [
                "actor_username": currentUser.username,
                "device_name": body.name,
                "platform": body.platform.rawValue,
                "ip": req.clientIP,
            ])
            throw error
        }
    }

    func update(_ req: Request) async throws -> DeviceResponse {
        guard let id = req.parameters.get("id", as: UUID.self) else { throw Abort(.badRequest) }
        let body = try req.content.decode(UpdateDeviceRequest.self)
        let device = try await deviceFeature.updateDevice(
            try req.user,
            id,
            body.name,
            body.pushToken,
            body.isActive,
            body.deliveryEnabled
        )
        return try DeviceResponse(device)
    }

    func delete(_ req: Request) async throws -> HTTPStatus {
        let currentUser = try req.user
        guard let id = req.parameters.get("id", as: UUID.self) else { throw Abort(.badRequest) }
        do {
            try await deviceFeature.deleteDevice(currentUser, id)
            auditLogger.log("device.delete", req: req, metadata: [
                "actor_username": currentUser.username,
                "device_id": id.uuidString,
                "ip": req.clientIP,
            ])
            return .noContent
        } catch {
            auditLogger.logError("device.delete", req: req, error: error, metadata: [
                "actor_username": currentUser.username,
                "device_id": id.uuidString,
                "ip": req.clientIP,
            ])
            throw error
        }
    }
}

// MARK: - DTOs

struct DeviceResponse: Content {
    let id: UUID
    let userID: UUID
    let name: String
    let platform: Platform
    let pushType: PushType
    let isActive: Bool
    let deliveryEnabled: Bool
    let createdAt: Date?
    let lastActivityAt: Date?

    init(_ device: Device) throws {
        self.id = try device.requireID()
        self.userID = device.$user.id
        self.name = device.name
        self.platform = device.platform
        self.pushType = device.pushType
        self.isActive = device.isActive
        self.deliveryEnabled = device.deliveryEnabled
        self.createdAt = device.createdAt
        self.lastActivityAt = device.lastActivityAt
    }
}

struct RegisterDeviceRequest: Content, Validatable {
    let name: String
    let platform: Platform
    let pushType: PushType
    let pushToken: String
    let deliveryEnabled: Bool?

    init(
        name: String,
        platform: Platform,
        pushType: PushType,
        pushToken: String,
        deliveryEnabled: Bool? = nil
    ) {
        self.name = name
        self.platform = platform
        self.pushType = pushType
        self.pushToken = pushToken
        self.deliveryEnabled = deliveryEnabled
    }

    static func validations(_ validations: inout Validations) {
        validations.add("name", as: String.self, is: .count(3...))
    }
}

struct UpdateDeviceRequest: Content {
    let name: String?
    let pushToken: String?
    let isActive: Bool?
    let deliveryEnabled: Bool?

    init(
        name: String?,
        pushToken: String?,
        isActive: Bool?,
        deliveryEnabled: Bool? = nil
    ) {
        self.name = name
        self.pushToken = pushToken
        self.isActive = isActive
        self.deliveryEnabled = deliveryEnabled
    }
}
