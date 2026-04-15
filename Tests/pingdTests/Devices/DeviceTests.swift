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
                    try req.content.encode(UpdateDeviceRequest(name: "Vi's New iPhone", pushToken: nil, isActive: nil))
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let device = try res.content.decode(DeviceResponse.self)
                    #expect(device.name == "Vi's New iPhone")
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
