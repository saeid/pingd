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
        tokenClient: services.tokenClient,
        deviceClient: services.deviceClient,
        auditLogger: services.auditLogger
    ))

    // Resolve token if present, otherwise anonymous
    let optionalAuth = api.grouped(
        OptionalTokenAuthMiddleware(tokenClient: services.tokenClient, now: services.now)
    )
    try optionalAuth.register(collection: TopicController(
        topicFeature: services.topicFeature,
        authClient: services.authClient,
        auditLogger: services.auditLogger
    ))
    try optionalAuth.register(collection: MessageController(
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
    try protected.register(collection: DispatchController(
        dispatchFeature: services.dispatchFeature,
        pushProvider: services.pushProvider
    ))
}
