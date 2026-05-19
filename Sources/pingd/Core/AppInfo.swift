import Vapor

struct AppInfo {
    let version: String
    let build: String

    static var current: Self {
        AppInfo(
            version: ProcessInfo.processInfo.environment["APP_VERSION"] ?? "dev",
            build: ProcessInfo.processInfo.environment["APP_BUILD"] ?? "0"
        )
    }
}
