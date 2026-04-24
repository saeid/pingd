import Vapor

enum DeviceError: AbortError {
    case notFound
    case accessDenied

    var status: HTTPResponseStatus {
        switch self {
        case .notFound: .notFound
        case .accessDenied: .forbidden
        }
    }

    var reason: String {
        switch self {
        case .notFound: "Device not found"
        case .accessDenied: "Access denied"
        }
    }
}

struct DeviceFeature {
    let listDevices: @Sendable (_ currentUser: User) async throws -> [Device]

    let registerDevice: @Sendable (
        _ currentUser: User,
        _ name: String,
        _ platform: Platform,
        _ pushType: PushType,
        _ pushToken: String
    ) async throws -> Device

    let updateDevice: @Sendable (
        _ currentUser: User,
        _ deviceID: UUID,
        _ name: String?,
        _ pushToken: String?,
        _ isActive: Bool?
    ) async throws -> Device

    let deleteDevice: @Sendable (
        _ currentUser: User,
        _ deviceID: UUID
    ) async throws -> Void
}

extension DeviceFeature {
    static func live(deviceClient: DeviceClient) -> Self {
        DeviceFeature(
            listDevices: { currentUser in
                if currentUser.role == .admin {
                    return try await deviceClient.list()
                }
                let userID = try currentUser.requireID()
                return try await deviceClient.listForUser(userID)
            },
            registerDevice: { currentUser, name, platform, pushType, pushToken in
                let userID = try currentUser.requireID()
                if let existing = try await deviceClient.findByPushToken(pushToken) {
                    let deviceID = try existing.requireID()
                    guard let updated = try await deviceClient.update(deviceID, name, nil, true) else {
                        throw DeviceError.notFound
                    }
                    return updated
                }
                return try await deviceClient.create(userID, name, platform, pushType, pushToken)
            },
            updateDevice: { currentUser, deviceID, name, pushToken, isActive in
                guard let device = try await deviceClient.get(deviceID) else {
                    throw DeviceError.notFound
                }
                let ownerID = device.$user.id
                let currentUserID = try currentUser.requireID()
                guard currentUser.role == .admin || currentUserID == ownerID else {
                    throw DeviceError.accessDenied
                }
                guard let updated = try await deviceClient.update(deviceID, name, pushToken, isActive) else {
                    throw DeviceError.notFound
                }
                return updated
            },
            deleteDevice: { currentUser, deviceID in
                guard let device = try await deviceClient.get(deviceID) else {
                    throw DeviceError.notFound
                }
                let ownerID = device.$user.id
                let currentUserID = try currentUser.requireID()
                guard currentUser.role == .admin || currentUserID == ownerID else {
                    throw DeviceError.accessDenied
                }
                try await deviceClient.delete(deviceID)
            }
        )
    }
}
