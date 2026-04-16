import Fluent
import FluentSQLiteDriver
import NIOSSL
import Vapor

// configures your application
public func configure(_ app: Application) async throws {
    app.middleware.use(RequestLoggerMiddleware())

    if app.environment == .testing {
        app.databases.use(DatabaseConfigurationFactory.sqlite(.memory), as: .sqlite)
    } else {
        app.databases.use(DatabaseConfigurationFactory.sqlite(.file("pingddb.sqlite")), as: .sqlite)
        app.logger.info("Starting Pingd \(AppInfo.current.version) (build \(AppInfo.current.build))")
        app.logger.info("Database: pingddb.sqlite")
        app.logger.info("Environment: \(app.environment.name)")
    }

    app.migrations.add([
        CreateUser(),
        CreateTopic(),
        CreateToken(),
        CreatePermission(),
        CreateMessage(),
        CreateDevice(),
        CreateDeviceSubscription(),
        CreateMessageDelivery(),
    ])

    if app.environment != .testing {
        app.migrations.add(SeedAdminUser())
    }

    let services = AppDependencies.live(with: app)

    // register routes
    try routes(app, services)

    // start dispatch worker (not in tests)
    if app.environment != .testing, let worker = services.dispatchWorker {
        Task { await worker.start() }
        app.logger.info("Dispatch worker started")
    }
}
