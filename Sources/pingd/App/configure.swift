import Fluent
import FluentSQLiteDriver
import NIOSSL
import Vapor

// configures your application
public func configure(_ app: Application) async throws {
    // uncomment to serve files from /Public folder
    // app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))

    app.databases.use(DatabaseConfigurationFactory.sqlite(.file("pingddb.sqlite")), as: .sqlite)

    app.migrations.add([
        CreateUser(),
        CreateTopic(),
        CreateToken(),
        CreatePermission(),
        CreateMessageDelivery(),
        CreateMessage(),
        CreateDeviceSubscription(),
        CreateDevice(),
    ])

    // register routes
    try routes(app)
}
