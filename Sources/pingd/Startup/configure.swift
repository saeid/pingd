import Fluent
import FluentSQLiteDriver
import NIOSSL
import Vapor

// configures your application
public func configure(_ app: Application) async throws {
    app.middleware.use(RequestLoggerMiddleware())

    app.databases.use(DatabaseConfigurationFactory.sqlite(.file("pingddb.sqlite")), as: .sqlite)

    app.logger.info("Starting Pingd \(AppInfo.current.version) (build \(AppInfo.current.build))")
    app.logger.info("Database: pingddb.sqlite")
    app.logger.info("Environment: \(app.environment.name)")

    app.migrations.add([
        CreateUser(),
        CreateTopic(),
        CreateToken(),
        CreatePermission(),
        CreateMessage(),
        CreateDevice(),
        CreateDeviceSubscription(),
        CreateMessageDelivery(),
        SeedAdminUser(),
    ])

    let services = AppDependencies.live(with: app)

    // register routes
    try routes(app, services)
}
