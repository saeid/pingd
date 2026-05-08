import Vapor

func routes(_ app: Application, _ services: AppDependencies) throws {
    let rateLimit = RateLimitMiddleware(
        rateLimiter: app.rateLimiter,
        now: services.now
    )
    let api = app.routes.grouped(rateLimit)

    // Public
    try api.register(collection: HealthController(
        healthClient: services.healthClient,
        appInfo: services.appInfo
    ))
    try api.register(collection: AuthController(
        authFeature: services.authFeature,
        userClient: services.userClient,
        authClient: services.authClient,
        tokenClient: services.tokenClient,
        deviceClient: services.deviceClient,
        now: services.now,
        auditLogger: services.auditLogger
    ))
    try api.register(collection: WebPushController(pushProvider: services.pushProvider))

    let webhookReceiveRoutes = app.routes.grouped(WebhookRateLimitMiddleware(
        rateLimiter: app.rateLimiter,
        now: services.now
    ))
    try webhookReceiveRoutes.register(collection: WebhookReceiveController(
        webhookFeature: services.webhookFeature,
        now: services.now,
        auditLogger: services.auditLogger
    ))

    // Resolve token if present, otherwise anonymous
    let optionalAuth = api.grouped(
        OptionalTokenAuthMiddleware(tokenClient: services.tokenClient, now: services.now)
    )
    try optionalAuth.register(collection: TopicController(
        topicFeature: services.topicFeature,
        auditLogger: services.auditLogger
    ))
    let publishRateLimit = PublishRateLimitMiddleware(
        rateLimiter: app.rateLimiter,
        now: services.now
    )
    try optionalAuth.grouped(publishRateLimit).register(collection: MessageController(
        messageFeature: services.messageFeature,
        now: services.now,
        auditLogger: services.auditLogger
    ))

    try optionalAuth.register(collection: SSEController(
        topicBroadcaster: services.topicBroadcaster,
        topicFeature: services.topicFeature
    ))

    // Protected
    let protected = api.grouped(
        TokenAuthMiddleware(tokenClient: services.tokenClient, now: services.now)
    )
    protected.get("me") { req in
        try UserResponse(req.user)
    }
    try protected.register(collection: UserController(
        userFeature: services.userFeature,
        authClient: services.authClient,
        auditLogger: services.auditLogger
    ))
    try protected.register(collection: TokenController(
        tokenFeature: services.tokenFeature,
        now: services.now,
        auditLogger: services.auditLogger
    ))
    try protected.register(collection: DeviceController(
        deviceFeature: services.deviceFeature,
        auditLogger: services.auditLogger
    ))
    try protected.register(collection: SubscriptionController(
        subscriptionFeature: services.subscriptionFeature,
        auditLogger: services.auditLogger
    ))
    try protected.register(collection: PermissionController(
        permissionFeature: services.permissionFeature,
        auditLogger: services.auditLogger
    ))
    try protected.register(collection: TopicShareController(
        topicShareFeature: services.topicShareFeature,
        auditLogger: services.auditLogger
    ))
    try protected.register(collection: DispatchController(
        dispatchFeature: services.dispatchFeature,
        pushProvider: services.pushProvider
    ))
    try protected.register(collection: WebhookAdminController(
        webhookFeature: services.webhookFeature,
        auditLogger: services.auditLogger
    ))
}
