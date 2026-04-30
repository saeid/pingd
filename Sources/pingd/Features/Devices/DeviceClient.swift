import Fluent
import Vapor
import Foundation

struct DeviceClient {
    let list: @Sendable () async throws -> [Device]
    let listForUser: @Sendable (_ userID: UUID) async throws -> [Device]
    let get: @Sendable (UUID) async throws -> Device?
    let findByPushToken: @Sendable (_ pushToken: String) async throws -> Device?
    let create: @Sendable (
        _ userID: UUID,
        _ name: String,
        _ platform: Platform,
        _ pushType: PushType,
        _ pushToken: String,
        _ deliveryEnabled: Bool
    ) async throws -> Device
    let update: @Sendable (
        UUID,
        _ name: String?,
        _ pushToken: String?,
        _ isActive: Bool?,
        _ deliveryEnabled: Bool?
    ) async throws -> Device?
    let transferInactiveDevice: @Sendable (
        _ existingDeviceID: UUID,
        _ userID: UUID,
        _ name: String,
        _ platform: Platform,
        _ pushType: PushType,
        _ pushToken: String,
        _ deliveryEnabled: Bool
    ) async throws -> Device
    let delete: @Sendable (UUID) async throws -> Void
}

extension DeviceClient {
    static func live(app: Application) -> Self {
        DeviceClient(
            list: {
                try await Device.query(on: app.db).all()
            },
            listForUser: { userID in
                try await Device.query(on: app.db)
                    .filter(\.$user.$id == userID)
                    .all()
            },
            get: { id in
                try await Device.find(id, on: app.db)
            },
            findByPushToken: { pushToken in
                try await Device.query(on: app.db)
                    .filter(\.$pushToken == pushToken)
                    .first()
            },
            create: { userID, name, platform, pushType, pushToken, deliveryEnabled in
                let device = Device(
                    userID: userID,
                    name: name,
                    platform: platform,
                    pushType: pushType,
                    pushToken: pushToken,
                    deliveryEnabled: deliveryEnabled
                )
                try await device.save(on: app.db)
                return device
            },
            update: { id, name, pushToken, isActive, deliveryEnabled in
                guard let device = try await Device.find(id, on: app.db) else {
                    return nil
                }
                if let name { device.name = name }
                if let pushToken { device.pushToken = pushToken }
                if let isActive { device.isActive = isActive }
                if let deliveryEnabled { device.deliveryEnabled = deliveryEnabled }
                try await device.save(on: app.db)
                return device
            },
            transferInactiveDevice: { existingDeviceID, userID, name, platform, pushType, pushToken, deliveryEnabled in
                try await app.db.transaction { database in
                    guard let existing = try await Device.find(existingDeviceID, on: database) else {
                        throw DeviceError.notFound
                    }
                    guard !existing.isActive else {
                        throw DeviceError.pushTokenInUse
                    }
                    try await existing.delete(on: database)
                    let device = Device(
                        userID: userID,
                        name: name,
                        platform: platform,
                        pushType: pushType,
                        pushToken: pushToken,
                        deliveryEnabled: deliveryEnabled
                    )
                    try await device.save(on: database)
                    return device
                }
            },
            delete: { id in
                guard let device = try await Device.find(id, on: app.db) else { return }
                try await device.delete(on: app.db)
            }
        )
    }

    static func mock(
        list: @escaping @Sendable () async throws -> [Device] = { [] },
        listForUser: @escaping @Sendable (UUID) async throws -> [Device] = { _ in [] },
        get: @escaping @Sendable (UUID) async throws -> Device? = { _ in nil },
        findByPushToken: @escaping @Sendable (String) async throws -> Device? = { _ in nil },
        create: @escaping @Sendable (UUID, String, Platform, PushType, String, Bool) async throws -> Device = { userID, name, platform, pushType, pushToken, deliveryEnabled in
            Device(userID: userID, name: name, platform: platform, pushType: pushType, pushToken: pushToken, deliveryEnabled: deliveryEnabled)
        },
        update: @escaping @Sendable (UUID, String?, String?, Bool?, Bool?) async throws -> Device? = { _, _, _, _, _ in nil },
        transferInactiveDevice: @escaping @Sendable (UUID, UUID, String, Platform, PushType, String, Bool) async throws -> Device = { _, userID, name, platform, pushType, pushToken, deliveryEnabled in
            Device(userID: userID, name: name, platform: platform, pushType: pushType, pushToken: pushToken, deliveryEnabled: deliveryEnabled)
        },
        delete: @escaping @Sendable (UUID) async throws -> Void = { _ in }
    ) -> Self {
        DeviceClient(
            list: list,
            listForUser: listForUser,
            get: get,
            findByPushToken: findByPushToken,
            create: create,
            update: update,
            transferInactiveDevice: transferInactiveDevice,
            delete: delete
        )
    }
}
