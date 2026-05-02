import Vapor

struct AppDependencies {
    let appInfo: AppInfo
    let now: @Sendable () -> Date
    let healthClient: HealthClient
    let authClient: AuthClient
    let tokenClient: TokenClient
    let userClient: UserClient
    let topicClient: TopicClient
    let messageClient: MessageClient
    let deviceClient: DeviceClient
    let subscriptionClient: SubscriptionClient
    let permissionClient: PermissionClient
    let dispatchClient: DispatchClient
    let webhookClient: WebhookClient
    let pushProvider: PushProvider
    let topicBroadcaster: TopicBroadcaster
    let authFeature: AuthFeature
    let userFeature: UserFeature
    let tokenFeature: TokenFeature
    let topicFeature: TopicFeature
    let messageFeature: MessageFeature
    let deviceFeature: DeviceFeature
    let subscriptionFeature: SubscriptionFeature
    let permissionFeature: PermissionFeature
    let dispatchFeature: DispatchFeature
    let webhookFeature: WebhookFeature
    let dispatchWorker: DispatchWorker?
    let auditLogger: AuditLogger
}

extension AppDependencies {
    static func live(
        with app: Application,
        apnsMode: APNSPushMode?,
        webPushConfiguration: WebPushConfiguration?
    ) -> AppDependencies {
        let now: @Sendable () -> Date = { Date() }
        let authClient = AuthClient.live()
        let tokenClient = TokenClient.live(app: app)
        let userClient = UserClient.live(app: app)
        let topicClient = TopicClient.live(app: app)
        let messageClient = MessageClient.live(app: app)
        let deviceClient = DeviceClient.live(app: app)
        let subscriptionClient = SubscriptionClient.live(app: app)
        let permissionClient = PermissionClient.live(app: app)
        let dispatchClient = DispatchClient.live(app: app)
        let webhookClient = WebhookClient.live(app: app)
        let topicBroadcaster = TopicBroadcaster()

        let apnsProvider: PushProvider? = switch apnsMode {
        case .direct(let config):
            .apns(application: app, config: config, logger: app.logger)
        case .relay(let config):
            .relay(config: config, logger: app.logger)
        case nil:
            nil
        }

        let webPushProvider = webPushConfiguration.map {
            PushProvider.webPush(config: $0, logger: app.logger)
        }

        let pushProvider: PushProvider = if apnsProvider == nil && webPushProvider == nil {
            .mock(logger: app.logger)
        } else {
            .routed(apns: apnsProvider, webPush: webPushProvider, logger: app.logger)
        }

        let dispatchFeature = DispatchFeature.live(
            dispatchClient: dispatchClient,
            subscriptionClient: subscriptionClient,
            deviceClient: deviceClient
        )

        let dispatchWorker = DispatchWorker(
            dispatchClient: dispatchClient,
            deviceClient: deviceClient,
            pushProvider: pushProvider,
            messageClient: messageClient,
            logger: app.logger,
            now: now
        )

        return AppDependencies(
            appInfo: AppInfo.current,
            now: now,
            healthClient: HealthClient.live(app: app),
            authClient: authClient,
            tokenClient: tokenClient,
            userClient: userClient,
            topicClient: topicClient,
            messageClient: messageClient,
            deviceClient: deviceClient,
            subscriptionClient: subscriptionClient,
            permissionClient: permissionClient,
            dispatchClient: dispatchClient,
            webhookClient: webhookClient,
            pushProvider: pushProvider,
            topicBroadcaster: topicBroadcaster,
            authFeature: AuthFeature.live(
                userClient: userClient,
                authClient: authClient,
                tokenClient: tokenClient,
                now: now
            ),
            userFeature: UserFeature.live(userClient: userClient, authClient: authClient),
            tokenFeature: TokenFeature.live(tokenClient: tokenClient, userClient: userClient),
            topicFeature: TopicFeature.live(
                topicClient: topicClient,
                authClient: authClient,
                permissionClient: permissionClient,
                messageClient: messageClient,
                subscriptionClient: subscriptionClient,
                dispatchClient: dispatchClient
            ),
            messageFeature: MessageFeature.live(
                topicClient: topicClient,
                authClient: authClient,
                permissionClient: permissionClient,
                messageClient: messageClient,
                dispatchFeature: dispatchFeature,
                topicBroadcaster: topicBroadcaster
            ),
            deviceFeature: DeviceFeature.live(deviceClient: deviceClient),
            subscriptionFeature: SubscriptionFeature.live(
                subscriptionClient: subscriptionClient,
                deviceClient: deviceClient,
                topicClient: topicClient,
                userClient: userClient,
                authClient: authClient,
                permissionClient: permissionClient
            ),
            permissionFeature: PermissionFeature.live(
                permissionClient: permissionClient,
                userClient: userClient
            ),
            dispatchFeature: dispatchFeature,
            webhookFeature: WebhookFeature.live(
                webhookClient: webhookClient,
                topicClient: topicClient,
                messageClient: messageClient,
                dispatchFeature: dispatchFeature,
                topicBroadcaster: topicBroadcaster
            ),
            dispatchWorker: dispatchWorker,
            auditLogger: AuditLogger(logger: app.logger)
        )
    }

    func withReplacing(
        appInfo: AppInfo? = nil,
        now: (@Sendable () -> Date)? = nil,
        healthClient: HealthClient? = nil,
        authClient: AuthClient? = nil,
        tokenClient: TokenClient? = nil,
        userClient: UserClient? = nil,
        topicClient: TopicClient? = nil,
        messageClient: MessageClient? = nil,
        deviceClient: DeviceClient? = nil,
        subscriptionClient: SubscriptionClient? = nil,
        permissionClient: PermissionClient? = nil,
        dispatchClient: DispatchClient? = nil,
        webhookClient: WebhookClient? = nil,
        pushProvider: PushProvider? = nil,
        topicBroadcaster: TopicBroadcaster? = nil,
        authFeature: AuthFeature? = nil,
        userFeature: UserFeature? = nil,
        tokenFeature: TokenFeature? = nil,
        topicFeature: TopicFeature? = nil,
        messageFeature: MessageFeature? = nil,
        deviceFeature: DeviceFeature? = nil,
        subscriptionFeature: SubscriptionFeature? = nil,
        permissionFeature: PermissionFeature? = nil,
        dispatchFeature: DispatchFeature? = nil,
        webhookFeature: WebhookFeature? = nil,
        dispatchWorker: DispatchWorker? = nil,
        auditLogger: AuditLogger? = nil
    ) -> AppDependencies {
        AppDependencies(
            appInfo: appInfo ?? self.appInfo,
            now: now ?? self.now,
            healthClient: healthClient ?? self.healthClient,
            authClient: authClient ?? self.authClient,
            tokenClient: tokenClient ?? self.tokenClient,
            userClient: userClient ?? self.userClient,
            topicClient: topicClient ?? self.topicClient,
            messageClient: messageClient ?? self.messageClient,
            deviceClient: deviceClient ?? self.deviceClient,
            subscriptionClient: subscriptionClient ?? self.subscriptionClient,
            permissionClient: permissionClient ?? self.permissionClient,
            dispatchClient: dispatchClient ?? self.dispatchClient,
            webhookClient: webhookClient ?? self.webhookClient,
            pushProvider: pushProvider ?? self.pushProvider,
            topicBroadcaster: topicBroadcaster ?? self.topicBroadcaster,
            authFeature: authFeature ?? self.authFeature,
            userFeature: userFeature ?? self.userFeature,
            tokenFeature: tokenFeature ?? self.tokenFeature,
            topicFeature: topicFeature ?? self.topicFeature,
            messageFeature: messageFeature ?? self.messageFeature,
            deviceFeature: deviceFeature ?? self.deviceFeature,
            subscriptionFeature: subscriptionFeature ?? self.subscriptionFeature,
            permissionFeature: permissionFeature ?? self.permissionFeature,
            dispatchFeature: dispatchFeature ?? self.dispatchFeature,
            webhookFeature: webhookFeature ?? self.webhookFeature,
            dispatchWorker: dispatchWorker ?? self.dispatchWorker,
            auditLogger: auditLogger ?? self.auditLogger
        )
    }
}
