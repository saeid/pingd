import Vapor

struct HealthResponse: Content {
    let system: String
    let database: String
    let version: String
    let build: String

    init(
        result: (system: String, database: String),
        info: AppInfo
    ) {
        system = result.system
        database = result.database
        version = info.version
        build = info.build
    }
}
