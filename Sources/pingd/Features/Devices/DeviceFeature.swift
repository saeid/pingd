import Fluent
import Vapor

enum DeviceError: AbortError {
    case notFound
    case accessDenied
    case pushTokenInUse

    var status: HTTPResponseStatus {
        switch self {
        case .notFound: .notFound
        case .accessDenied: .forbidden
        case .pushTokenInUse: .conflict
        }
    }

    var reason: String {
        switch self {
        case .notFound: "Device not found"
        case .accessDenied: "Access denied"
        case .pushTokenInUse: "Push token is already registered to an active device"
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
        _ pushToken: String,
        _ deliveryEnabled: Bool
    ) async throws -> Device

    let updateDevice: @Sendable (
        _ currentUser: User,
        _ deviceID: UUID,
        _ name: String?,
        _ pushToken: String?,
        _ isActive: Bool?,
        _ deliveryEnabled: Bool?
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
            registerDevice: { currentUser, name, platform, pushType, pushToken, deliveryEnabled in
                let userID = try currentUser.requireID()
                if let existing = try await deviceClient.findByPushToken(pushToken) {
                    let deviceID = try existing.requireID()
                    if existing.$user.id != userID {
                        guard !existing.isActive else {
                            throw DeviceError.pushTokenInUse
                        }
                        do {
                            return try await deviceClient.transferInactiveDevice(
                                deviceID,
                                userID,
                                name,
                                platform,
                                pushType,
                                pushToken,
                                deliveryEnabled
                            )
                        } catch let error as any DatabaseError where error.isConstraintFailure {
                            throw DeviceError.pushTokenInUse
                        }
                    }
                    guard let updated = try await deviceClient.update(deviceID, name, nil, true, deliveryEnabled) else {
                        throw DeviceError.notFound
                    }
                    return updated
                }
                do {
                    return try await deviceClient.create(userID, name, platform, pushType, pushToken, deliveryEnabled)
                } catch let error as any DatabaseError where error.isConstraintFailure {
                    throw DeviceError.pushTokenInUse
                }
            },
            updateDevice: { currentUser, deviceID, name, pushToken, isActive, deliveryEnabled in
                guard let device = try await deviceClient.get(deviceID) else {
                    throw DeviceError.notFound
                }
                let ownerID = device.$user.id
                let currentUserID = try currentUser.requireID()
                guard currentUser.role == .admin || currentUserID == ownerID else {
                    throw DeviceError.accessDenied
                }
                do {
                    guard let updated = try await deviceClient.update(deviceID, name, pushToken, isActive, deliveryEnabled) else {
                        throw DeviceError.notFound
                    }
                    return updated
                } catch let error as any DatabaseError where error.isConstraintFailure {
                    throw DeviceError.pushTokenInUse
                }
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
