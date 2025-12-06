import Vapor

struct AppDependencies {
    let appInfo: AppInfo
    let healthClient: HealthClient
}

extension AppDependencies {
    static func live(with app: Application) -> AppDependencies {
        AppDependencies(
            appInfo: AppInfo.current,
            healthClient: HealthClient.live(app: app)
        )
    }

    static func test(
        appInfo: AppInfo = AppInfo(version: "test", build: "test"),
        healthClient: HealthClient = .mock()
    ) -> AppDependencies {
        AppDependencies(
            appInfo: appInfo,
            healthClient: healthClient
        )
    }

    func withReplacing(
        appInfo: AppInfo? = nil,
        healthClient: HealthClient? = nil
    ) -> AppDependencies {
        AppDependencies(
            appInfo: appInfo ?? self.appInfo,
            healthClient: healthClient ?? self.healthClient
        )
    }
}
