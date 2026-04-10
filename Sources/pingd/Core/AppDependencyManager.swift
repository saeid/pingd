import Vapor

struct AppDependencies {
    let appInfo: AppInfo
    let now: () -> Date
    let healthClient: HealthClient
    let authClient: AuthClient
    let tokenClient: TokenClient
    let userClient: UserClient
}

extension AppDependencies {
    static func live(with app: Application) -> AppDependencies {
        AppDependencies(
            appInfo: AppInfo.current,
            now: { Date() },
            healthClient: HealthClient.live(app: app),
            authClient: AuthClient.live(),
            tokenClient: TokenClient.live(app: app),
            userClient: UserClient.live(app: app)
        )
    }

    static func test(
        appInfo: AppInfo = AppInfo(version: "test", build: "test"),
        fixedNow: Date,
        healthClient: HealthClient = .mock(),
        authClient: AuthClient = .mock(),
        tokenClient: TokenClient = .mock(),
        userClient: UserClient = .mock()
    ) -> AppDependencies {
        AppDependencies(
            appInfo: appInfo,
            now: { fixedNow },
            healthClient: healthClient,
            authClient: authClient,
            tokenClient: tokenClient,
            userClient: userClient
        )
    }

    func withReplacing(
        appInfo: AppInfo? = nil,
        now: (() -> Date)? = nil,
        healthClient: HealthClient? = nil,
        authClient: AuthClient? = nil,
        tokenClient: TokenClient? = nil,
        userClient: UserClient? = nil
    ) -> AppDependencies {
        AppDependencies(
            appInfo: appInfo ?? self.appInfo,
            now: now ?? self.now,
            healthClient: healthClient ?? self.healthClient,
            authClient: authClient ?? self.authClient,
            tokenClient: tokenClient ?? self.tokenClient,
            userClient: userClient ?? self.userClient
        )
    }
}
