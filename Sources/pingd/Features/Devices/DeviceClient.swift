import Fluent
import Vapor
import Foundation

struct DeviceClient {
    let list: @Sendable () async throws -> [Device]
    let listForUser: @Sendable (_ userID: UUID) async throws -> [Device]
    let get: @Sendable (UUID) async throws -> Device?
    let create: @Sendable (
        _ userID: UUID,
        _ name: String,
        _ platform: Platform,
        _ pushType: PushType,
        _ pushToken: String
    ) async throws -> Device
    let update: @Sendable (
        UUID,
        _ name: String?,
        _ pushToken: String?,
        _ isActive: Bool?
    ) async throws -> Device?
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
            create: { userID, name, platform, pushType, pushToken in
                let device = Device(
                    userID: userID,
                    name: name,
                    platform: platform,
                    pushType: pushType,
                    pushToken: pushToken
                )
                try await device.save(on: app.db)
                return device
            },
            update: { id, name, pushToken, isActive in
                guard let device = try await Device.find(id, on: app.db) else {
                    return nil
                }
                if let name { device.name = name }
                if let pushToken { device.pushToken = pushToken }
                if let isActive { device.isActive = isActive }
                try await device.save(on: app.db)
                return device
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
        create: @escaping @Sendable (UUID, String, Platform, PushType, String) async throws -> Device = { userID, name, platform, pushType, pushToken in
            Device(userID: userID, name: name, platform: platform, pushType: pushType, pushToken: pushToken)
        },
        update: @escaping @Sendable (UUID, String?, String?, Bool?) async throws -> Device? = { _, _, _, _ in nil },
        delete: @escaping @Sendable (UUID) async throws -> Void = { _ in }
    ) -> Self {
        DeviceClient(list: list, listForUser: listForUser, get: get, create: create, update: update, delete: delete)
    }
}
