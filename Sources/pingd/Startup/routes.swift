import Vapor

func routes(_ app: Application, _ services: AppDependencies) throws {
    // Public
    try app.routes.register(collection: HealthController(
        healthClient: services.healthClient,
        appInfo: services.appInfo
    ))
    try app.routes.register(collection: AuthController(
        authFeature: services.authFeature,
        tokenClient: services.tokenClient
    ))

    // Resolve token if present, otherwise anonymous
    let optionalAuth = app.routes.grouped(
        OptionalTokenAuthMiddleware(tokenClient: services.tokenClient, now: services.now)
    )
    try optionalAuth.register(collection: TopicController(
        topicFeature: services.topicFeature
    ))
    try optionalAuth.register(collection: MessageController(
        messageFeature: services.messageFeature,
        now: services.now
    ))

    // Protected
    let protected = app.routes.grouped(
        TokenAuthMiddleware(tokenClient: services.tokenClient, now: services.now)
    )
    protected.get("me") { req in
        try UserResponse(req.user)
    }
    try protected.register(collection: UserController(
        userFeature: services.userFeature,
        authClient: services.authClient
    ))
    try protected.register(collection: TokenController(
        tokenFeature: services.tokenFeature
    ))
    try protected.register(collection: DeviceController(
        deviceFeature: services.deviceFeature
    ))
    try protected.register(collection: SubscriptionController(
        subscriptionFeature: services.subscriptionFeature
    ))
    try protected.register(collection: PermissionController(
        permissionFeature: services.permissionFeature
    ))

    // Dispatch
    try protected.register(collection: DispatchController(
        dispatchFeature: services.dispatchFeature,
        topicBroadcaster: services.topicBroadcaster
    ))
}
