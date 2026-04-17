import Fluent
import FluentSQLiteDriver
import NIOSSL
import Vapor

// configures your application
public func configure(_ app: Application) async throws {
    app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory, defaultFile: "index.html"))
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

    if app.environment != .testing, !isMigrationCommand {
        app.lifecycle.use(TopicBroadcasterLifecycleHandler(broadcaster: services.topicBroadcaster))
    }

    // register routes
    try routes(app, services)

    if app.environment != .testing, !isMigrationCommand, let worker = services.dispatchWorker {
        app.lifecycle.use(DispatchWorkerLifecycleHandler(worker: worker))
    }

    // seed CLI token (not in tests)
    if app.environment != .testing {
        try await seedCLIToken(services: services, logger: app.logger)
    }
}
