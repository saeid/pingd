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
}
