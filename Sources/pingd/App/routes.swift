import Fluent
import Vapor

func routes(_ app: Application) throws {
    let services = app.services

    try app.routes.register(
        collection: HealthController(
            healthService: services.healthService,
            appInfo: services.appInfo
        )
    )
}
