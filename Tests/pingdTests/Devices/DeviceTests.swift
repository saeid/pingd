@testable import pingd
import Testing
import VaporTesting

extension PingdTests {
    @Test("Devices: POST /devices registers device")
    func registerDevice() async throws {
        try await withApp { app in
            let session = try await login(app, username: "vi", password: "password1")
            try await app.testing().test(
                .POST, "devices",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(RegisterDeviceRequest(
                        name: "Vi's iPhone",
                        platform: .ios,
                        pushType: .apns,
                        pushToken: "fake-push-token-abc123"
                    ))
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let device = try res.content.decode(DeviceResponse.self)
                    #expect(device.name == "Vi's iPhone")
                    #expect(device.platform == .ios)
                    #expect(device.isActive == true)
                    #expect(device.deliveryEnabled == true)
                }
            )
        }
    }

    @Test("Devices: POST /devices can register a subscriber without delivery")
    func registerDeviceWithDeliveryDisabled() async throws {
        try await withApp { app in
            let session = try await login(app, username: "vi", password: "password1")
            try await app.testing().test(
                .POST, "devices",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(RegisterDeviceRequest(
                        name: "Web Dashboard",
                        platform: .web,
                        pushType: .webPush,
                        pushToken: "dashboard-\(session.userID)",
                        deliveryEnabled: false
                    ))
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let device = try res.content.decode(DeviceResponse.self)
                    #expect(device.name == "Web Dashboard")
                    #expect(device.platform == .web)
                    #expect(device.isActive == true)
                    #expect(device.deliveryEnabled == false)
                }
            )
        }
    }

    @Test("Devices: POST /devices with short name returns 400")
    func registerDeviceShortName() async throws {
        try await withApp { app in
            let session = try await login(app, username: "vi", password: "password1")
            try await app.testing().test(
                .POST, "devices",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(RegisterDeviceRequest(
                        name: "ab",
                        platform: .ios,
                        pushType: .apns,
                        pushToken: "fake-push-token"
                    ))
                },
                afterResponse: { res in
                    #expect(res.status == .badRequest)
                }
            )
        }
    }

    @Test("Devices: POST /devices rejects another user's active push token")
    func registerDeviceWithActivePushTokenOwnedByOtherUser() async throws {
        try await withApp { app in
            try await seedDevices(app)
            let session = try await login(app, username: "vander", password: "letmein")
            try await app.testing().test(
                .POST, "devices",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(RegisterDeviceRequest(
                        name: "Shared iPhone",
                        platform: .ios,
                        pushType: .apns,
                        pushToken: "token-vi-iphone"
                    ))
                },
                afterResponse: { res in
                    #expect(res.status == .conflict)
                }
            )
        }
    }

    @Test("Devices: POST /devices allows another user to claim inactive push token after logout")
    func registerDeviceWithInactivePushTokenOwnedByOtherUser() async throws {
        try await withApp { app in
            try await seedDevices(app)
            let viSession = try await login(app, username: "vi", password: "password1")
            try await app.testing().test(
                .DELETE, "auth/logout",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: viSession.token)
                    req.headers.add(name: "X-Push-Token", value: "token-vi-iphone")
                },
                afterResponse: { res in
                    #expect(res.status == .noContent)
                }
            )

            let vanderSession = try await login(app, username: "vander", password: "letmein")
            try await app.testing().test(
                .POST, "devices",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: vanderSession.token)
                    try req.content.encode(RegisterDeviceRequest(
                        name: "Shared iPhone",
                        platform: .ios,
                        pushType: .apns,
                        pushToken: "token-vi-iphone"
                    ))
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let device = try res.content.decode(DeviceResponse.self)
                    #expect(device.name == "Shared iPhone")
                    #expect(device.isActive == true)
                    #expect(device.userID == vanderSession.userID)
                }
            )
        }
    }

    @Test("Devices: GET /devices as admin returns all devices")
    func listDevicesAsAdmin() async throws {
        try await withApp { app in
            try await seedDevices(app)
            let session = try await login(app, username: "jinx", password: "hunter2")
            try await app.testing().test(
                .GET, "devices",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let devices = try res.content.decode([DeviceResponse].self)
                    #expect(devices.count == 2)
                }
            )
        }
    }

    @Test("Devices: GET /devices as user returns own devices only")
    func listDevicesAsUser() async throws {
        try await withApp { app in
            try await seedDevices(app)
            let session = try await login(app, username: "vi", password: "password1")
            try await app.testing().test(
                .GET, "devices",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let devices = try res.content.decode([DeviceResponse].self)
                    #expect(devices.count == 1)
                    #expect(devices[0].name == "Vi's iPhone")
                }
            )
        }
    }

    @Test("Devices: PATCH /devices/:id as owner updates device")
    func updateDevice() async throws {
        try await withApp { app in
            try await seedDevices(app)
            let session = try await login(app, username: "vi", password: "password1")
            var deviceID: UUID?
            try await app.testing().test(
                .GET, "devices",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                },
                afterResponse: { res in
                    let devices = try res.content.decode([DeviceResponse].self)
                    deviceID = devices[0].id
                }
            )
            let id = try #require(deviceID)
            try await app.testing().test(
                .PATCH, "devices/\(id)",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(UpdateDeviceRequest(name: "Vi's New iPhone", pushToken: nil, isActive: nil, deliveryEnabled: false))
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let device = try res.content.decode(DeviceResponse.self)
                    #expect(device.name == "Vi's New iPhone")
                    #expect(device.deliveryEnabled == false)
                }
            )
        }
    }

    @Test("Devices: PATCH /devices/:id as non-owner returns 403")
    func updateDeviceAsOther() async throws {
        try await withApp { app in
            try await seedDevices(app)
            let viSession = try await login(app, username: "vi", password: "password1")
            var deviceID: UUID?
            try await app.testing().test(
                .GET, "devices",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: viSession.token)
                },
                afterResponse: { res in
                    let devices = try res.content.decode([DeviceResponse].self)
                    deviceID = devices[0].id
                }
            )
            let id = try #require(deviceID)
            let vanderSession = try await login(app, username: "vander", password: "letmein")
            try await app.testing().test(
                .PATCH, "devices/\(id)",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: vanderSession.token)
                    try req.content.encode(UpdateDeviceRequest(name: "Hacked", pushToken: nil, isActive: nil))
                },
                afterResponse: { res in
                    #expect(res.status == .forbidden)
                }
            )
        }
    }

    @Test("Devices: PATCH /devices/:id updates all fields together")
    func updateDeviceAllFields() async throws {
        try await withApp { app in
            try await seedDevices(app)
            let session = try await login(app, username: "vi", password: "password1")
            var deviceID: UUID?
            try await app.testing().test(
                .GET, "devices",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                },
                afterResponse: { res in
                    deviceID = try res.content.decode([DeviceResponse].self)[0].id
                }
            )
            let id = try #require(deviceID)
            try await app.testing().test(
                .PATCH, "devices/\(id)",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(UpdateDeviceRequest(
                        name: "Renamed",
                        pushToken: "new-token",
                        isActive: false,
                        deliveryEnabled: false
                    ))
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let device = try res.content.decode(DeviceResponse.self)
                    #expect(device.name == "Renamed")
                    #expect(device.isActive == false)
                    #expect(device.deliveryEnabled == false)
                }
            )
        }
    }

    @Test("Devices: PATCH /devices/:id deactivating preserves deliveryEnabled")
    func updateDeviceDeactivateKeepsDeliveryEnabled() async throws {
        try await withApp { app in
            try await seedDevices(app)
            let session = try await login(app, username: "vi", password: "password1")
            var deviceID: UUID?
            try await app.testing().test(
                .GET, "devices",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                },
                afterResponse: { res in
                    deviceID = try res.content.decode([DeviceResponse].self)[0].id
                }
            )
            let id = try #require(deviceID)
            try await app.testing().test(
                .PATCH, "devices/\(id)",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(UpdateDeviceRequest(
                        name: nil,
                        pushToken: nil,
                        isActive: false,
                        deliveryEnabled: nil
                    ))
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let device = try res.content.decode(DeviceResponse.self)
                    #expect(device.isActive == false)
                    #expect(device.deliveryEnabled == true)
                }
            )
        }
    }

    @Test("Devices: PATCH /devices/:id with no fields is a no-op")
    func updateDeviceNoOp() async throws {
        try await withApp { app in
            try await seedDevices(app)
            let session = try await login(app, username: "vi", password: "password1")
            var deviceID: UUID?
            var originalName: String?
            try await app.testing().test(
                .GET, "devices",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                },
                afterResponse: { res in
                    let devices = try res.content.decode([DeviceResponse].self)
                    deviceID = devices[0].id
                    originalName = devices[0].name
                }
            )
            let id = try #require(deviceID)
            let name = try #require(originalName)
            try await app.testing().test(
                .PATCH, "devices/\(id)",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(UpdateDeviceRequest(
                        name: nil,
                        pushToken: nil,
                        isActive: nil,
                        deliveryEnabled: nil
                    ))
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let device = try res.content.decode(DeviceResponse.self)
                    #expect(device.name == name)
                    #expect(device.isActive == true)
                    #expect(device.deliveryEnabled == true)
                }
            )
        }
    }

    @Test("Devices: PATCH /devices/:id can re-enable delivery on inactive device")
    func updateDeviceReenableDeliveryWhileInactive() async throws {
        try await withApp { app in
            try await seedDevices(app)
            let session = try await login(app, username: "vi", password: "password1")
            var deviceID: UUID?
            try await app.testing().test(
                .GET, "devices",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                },
                afterResponse: { res in
                    deviceID = try res.content.decode([DeviceResponse].self)[0].id
                }
            )
            let id = try #require(deviceID)
            try await app.testing().test(
                .PATCH, "devices/\(id)",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(UpdateDeviceRequest(
                        name: nil,
                        pushToken: nil,
                        isActive: false,
                        deliveryEnabled: false
                    ))
                },
                afterResponse: { _ in }
            )
            try await app.testing().test(
                .PATCH, "devices/\(id)",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                    try req.content.encode(UpdateDeviceRequest(
                        name: nil,
                        pushToken: nil,
                        isActive: nil,
                        deliveryEnabled: true
                    ))
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let device = try res.content.decode(DeviceResponse.self)
                    #expect(device.isActive == false)
                    #expect(device.deliveryEnabled == true)
                }
            )
        }
    }

    @Test("Devices: DELETE /devices/:id as owner deletes device")
    func deleteDevice() async throws {
        try await withApp { app in
            try await seedDevices(app)
            let session = try await login(app, username: "vi", password: "password1")
            var deviceID: UUID?
            try await app.testing().test(
                .GET, "devices",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                },
                afterResponse: { res in
                    let devices = try res.content.decode([DeviceResponse].self)
                    deviceID = devices[0].id
                }
            )
            let id = try #require(deviceID)
            try await app.testing().test(
                .DELETE, "devices/\(id)",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: session.token)
                },
                afterResponse: { res in
                    #expect(res.status == .noContent)
                }
            )
        }
    }
}
