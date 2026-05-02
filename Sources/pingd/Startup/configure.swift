import APNS
import APNSCore
import Crypto
import Fluent
import FluentSQLiteDriver
import Vapor
import VaporAPNS

func makeCORSConfiguration(from config: CORSConfig) -> CORSMiddleware.Configuration {
    let allowedOrigin: CORSMiddleware.AllowOriginSetting =
        config.allowsAllOrigins ? .all : .any(config.explicitOrigins)

    return CORSMiddleware.Configuration(
        allowedOrigin: allowedOrigin,
        allowedMethods: [.GET, .POST, .PATCH, .DELETE, .OPTIONS],
        allowedHeaders: [
            .accept,
            .authorization,
            .contentType,
            .origin,
            .xRequestedWith,
            .init("X-Topic-Password"),
        ]
    )
}

public func configure(_ app: Application) async throws {
    let isMigrationCommand = CommandLine.arguments.contains("migrate")
    let environmentVariables = app.environment == .testing ? [:] : ProcessInfo.processInfo.environment
    let appConfig = try AppConfig.load(environment: app.environment, environmentVariables: environmentVariables)
    app.appConfig = appConfig
    app.rateLimiter = RateLimiter()

    app.http.server.configuration.port = 7685
    app.middleware = .init()
    app.middleware.use(CORSMiddleware(configuration: makeCORSConfiguration(from: appConfig.cors)), at: .beginning)
    app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory, defaultFile: "index.html"))
    app.middleware.use(RequestLoggerMiddleware())
    app.middleware.use(ErrorMiddleware.default(environment: app.environment))

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
        CreateTopicWebhook(),
    ])

    if app.environment != .testing {
        app.migrations.add(SeedAdminUser())
    }

    if !isMigrationCommand {
        try await app.autoMigrate()
    }

    let apnsMode = app.environment == .testing ? nil : try PushProvider.loadAPNSConfiguration()
    let webPushConfiguration = app.environment == .testing ? nil : try PushProvider.loadWebPushConfiguration()

    switch apnsMode {
    case .direct(let config):
        let keyData = try String(contentsOfFile: config.keyPath, encoding: .utf8)
        let authMethod = APNSClientConfiguration.AuthenticationMethod.jwt(
            privateKey: try .loadFrom(string: keyData),
            keyIdentifier: config.keyID,
            teamIdentifier: config.teamID
        )
        await app.apns.configure(authMethod)
        app.logger.info("APNS configured in direct mode (\(config.environment))")
    case .relay(let config):
        app.logger.info("APNS configured in relay mode (\(config.baseURL))")
    case nil:
        app.logger.info("APNS not configured, using mock provider")
    }

    if webPushConfiguration == nil {
        app.logger.info("Web Push not configured")
    } else {
        app.logger.info("Web Push configured")
    }

    let services = AppDependencies.live(
        with: app,
        apnsMode: apnsMode,
        webPushConfiguration: webPushConfiguration
    )

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
