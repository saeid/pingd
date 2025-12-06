import Vapor

func routes(_ app: Application, _ services: AppDependencies) throws {
    try app.routes.register(
        collection: HealthController(
            healthClient: services.healthClient,
            appInfo: services.appInfo
        )
    )
}
