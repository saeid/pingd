import Vapor

struct AppDependencies {
    let appInfo: AppInfo
    let now: @Sendable () -> Date
    let healthClient: HealthClient
    let authClient: AuthClient
    let tokenClient: TokenClient
    let userClient: UserClient
    let authFeature: AuthFeature
    let userFeature: UserFeature
    let tokenFeature: TokenFeature
}

extension AppDependencies {
    static func live(with app: Application) -> AppDependencies {
        let now: @Sendable () -> Date = { Date() }
        let authClient = AuthClient.live()
        let tokenClient = TokenClient.live(app: app)
        let userClient = UserClient.live(app: app)
        return AppDependencies(
            appInfo: AppInfo.current,
            now: now,
            healthClient: HealthClient.live(app: app),
            authClient: authClient,
            tokenClient: tokenClient,
            userClient: userClient,
            authFeature: AuthFeature.live(
                userClient: userClient,
                authClient: authClient,
                tokenClient: tokenClient,
                now: now
            ),
            userFeature: UserFeature.live(userClient: userClient),
            tokenFeature: TokenFeature.live(tokenClient: tokenClient, userClient: userClient)
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
        let now: @Sendable () -> Date = { fixedNow }
        return AppDependencies(
            appInfo: appInfo,
            now: now,
            healthClient: healthClient,
            authClient: authClient,
            tokenClient: tokenClient,
            userClient: userClient,
            authFeature: AuthFeature.live(
                userClient: userClient,
                authClient: authClient,
                tokenClient: tokenClient,
                now: now
            ),
            userFeature: UserFeature.live(userClient: userClient),
            tokenFeature: TokenFeature.live(tokenClient: tokenClient, userClient: userClient)
        )
    }

    func withReplacing(
        appInfo: AppInfo? = nil,
        now: (@Sendable () -> Date)? = nil,
        healthClient: HealthClient? = nil,
        authClient: AuthClient? = nil,
        tokenClient: TokenClient? = nil,
        userClient: UserClient? = nil,
        authFeature: AuthFeature? = nil,
        userFeature: UserFeature? = nil,
        tokenFeature: TokenFeature? = nil
    ) -> AppDependencies {
        AppDependencies(
            appInfo: appInfo ?? self.appInfo,
            now: now ?? self.now,
            healthClient: healthClient ?? self.healthClient,
            authClient: authClient ?? self.authClient,
            tokenClient: tokenClient ?? self.tokenClient,
            userClient: userClient ?? self.userClient,
            authFeature: authFeature ?? self.authFeature,
            userFeature: userFeature ?? self.userFeature,
            tokenFeature: tokenFeature ?? self.tokenFeature
        )
    }
}
