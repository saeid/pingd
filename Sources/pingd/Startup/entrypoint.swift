import Logging
import NIOCore
import NIOPosix
import Vapor

@main
enum Entrypoint {
    static func main() async throws {
        var env = try Environment.detect()
        let logFormat = Environment.get("PINGD_LOG_FORMAT") ?? "text"
        try LoggingSystem.bootstrap(from: &env) { level in
            { label in
                if logFormat == "json" {
                    return JSONLogHandler(label: label, level: level)
                }
                return StreamLogHandler.standardOutput(
                    label: label,
                    metadataProvider: LoggingSystem.metadataProvider
                )
            }
        }

        let app = try await Application.make(env)

        do {
            try await configure(app)
            try await app.execute()
        } catch {
            app.logger.report(error: error)
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }
}
