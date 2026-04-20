import Fluent
import FluentSQLiteDriver
import Vapor

public func configure(_ app: Application) async throws {
    let isMigrationCommand = CommandLine.arguments.contains("migrate")
    let appConfig = try AppConfig.load(environment: app.environment)
    app.appConfig = appConfig

    app.http.server.configuration.port = 7685
    app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory, defaultFile: "index.html"))
    app.middleware.use(RequestLoggerMiddleware())

    if app.environment == .testing {
        app.databases.use(DatabaseConfigurationFactory.sqlite(.memory), as: .sqlite)
    } else {
        let dataDir = Environment.get("PINGD_DATA_DIR") ?? "data"
        try FileManager.default.createDirectory(atPath: dataDir, withIntermediateDirectories: true)
        let databasePath = URL(fileURLWithPath: dataDir, isDirectory: true)
            .appendingPathComponent("pingddb.sqlite")
            .path
        app.databases.use(DatabaseConfigurationFactory.sqlite(.file(databasePath)), as: .sqlite)
        app.logger.info("Starting Pingd \(AppInfo.current.version) (build \(AppInfo.current.build))")
        app.logger.info("Data directory: \(dataDir)")
        app.logger.info("Database: \(databasePath)")
        app.logger.info("Environment: \(app.environment.name)")
        app.logger.info("Rate limiting: \(appConfig.rateLimit.isEnabled ? "enabled" : "disabled")")
        app.logger.info("Rate limit: \(appConfig.rateLimit.count)/60s")
        app.logger.info(
            "CORS origins: \(appConfig.cors.allowsAllOrigins ? "*" : appConfig.cors.explicitOrigins.joined(separator: ", "))"
        )
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

    if !isMigrationCommand {
        try await app.autoMigrate()
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

    if app.environment != .testing, !isMigrationCommand {
        try await seedCLIToken(services: services, logger: app.logger)
    }
}
