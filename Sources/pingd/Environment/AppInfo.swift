import Vapor

struct AppInfo {
    let version: String
    let build: String

    static var current: Self {
        AppInfo(
            version: Environment.get("VERSION") ?? "0.0.1",
            build: Environment.get("BUILD") ?? "1"
        )
    }
}
