import Vapor

struct AppServices {
    let appInfo: AppInfo
    let healthService: HealthService
}

extension AppServices {
    static func live(with app: Application) -> AppServices {
        AppServices(
            appInfo: AppInfo.current,
            healthService: HealthService.live(app: app)
        )
    }

    static func test(
        appInfo: AppInfo = AppInfo(version: "test", build: "test"),
        healthService: HealthService = .mock()
    ) -> AppServices {
        AppServices(
            appInfo: appInfo,
            healthService: healthService
        )
    }

    func withReplacing(
        appInfo: AppInfo? = nil,
        healthService: HealthService? = nil
    ) -> AppServices {
        AppServices(
            appInfo: appInfo ?? self.appInfo,
            healthService: healthService ?? self.healthService
        )
    }
}

struct AppServicesKey: StorageKey {
    typealias Value = AppServices
}

extension Application {
    var services: AppServices {
        get {
            guard let value = storage[AppServicesKey.self] else {
                fatalError("AppServices not configured properly!")
            }
            return value
        }
        set {
            storage[AppServicesKey.self] = newValue
        }
    }
}
