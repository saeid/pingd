import Vapor

struct AppInfo {
    let version: String
    let build: String

    static var current: Self {
        AppInfo(
            version: "0.0.1",
            build: "1"
        )
    }
}
