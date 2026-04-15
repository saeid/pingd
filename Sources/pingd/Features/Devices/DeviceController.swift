import Vapor

struct DeviceController: RouteCollection, @unchecked Sendable {
    let deviceFeature: DeviceFeature

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
        try RegisterDeviceRequest.validate(content: req)
        let body = try req.content.decode(RegisterDeviceRequest.self)
        let device = try await deviceFeature.registerDevice(
            try req.user,
            body.name,
            body.platform,
            body.pushType,
            body.pushToken
        )
        return try DeviceResponse(device)
    }

    func update(_ req: Request) async throws -> DeviceResponse {
        guard let id = req.parameters.get("id", as: UUID.self) else { throw Abort(.badRequest) }
        let body = try req.content.decode(UpdateDeviceRequest.self)
        let device = try await deviceFeature.updateDevice(
            try req.user,
            id,
            body.name,
            body.pushToken,
            body.isActive
        )
        return try DeviceResponse(device)
    }

    func delete(_ req: Request) async throws -> HTTPStatus {
        guard let id = req.parameters.get("id", as: UUID.self) else { throw Abort(.badRequest) }
        try await deviceFeature.deleteDevice(try req.user, id)
        return .noContent
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
    let createdAt: Date?
    let lastActivityAt: Date?

    init(_ device: Device) throws {
        self.id = try device.requireID()
        self.userID = device.$user.id
        self.name = device.name
        self.platform = device.platform
        self.pushType = device.pushType
        self.isActive = device.isActive
        self.createdAt = device.createdAt
        self.lastActivityAt = device.lastActivityAt
    }
}

struct RegisterDeviceRequest: Content, Validatable {
    let name: String
    let platform: Platform
    let pushType: PushType
    let pushToken: String

    static func validations(_ validations: inout Validations) {
        validations.add("name", as: String.self, is: .count(3...))
    }
}

struct UpdateDeviceRequest: Content {
    let name: String?
    let pushToken: String?
    let isActive: Bool?
}
