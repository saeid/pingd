import Fluent
import Vapor

struct HealthService: @unchecked Sendable {
    let check: () async -> (system: String, database: String)
}

extension HealthService {
    static func live(app: Application) -> Self {
        HealthService {
            let system = "ok"
            var database = ""
            do {
                _ = try await app.db.transaction { _ in }
                database = "ok"
            } catch {
                app.logger.error("DB health check failed: \(error)")
                database = "failed"
            }
            return (system, database)
        }
    }

    static func mock(system: String = "ok", database: String = "ok") -> Self {
        HealthService {
            (system, database)
        }
    }
}
