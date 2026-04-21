import Vapor

struct AuditLogger: Sendable {
    let logger: Logger

    func log(_ event: String, req: Request, metadata: [String: String] = [:]) {
        var logMetadata: Logger.Metadata = [
            "audit": "true",
            "event": .string(event),
            "request_id": .string(req.id),
        ]
        for (key, value) in metadata {
            logMetadata[key] = .string(value)
        }
        logger.notice("\(event)", metadata: logMetadata)
    }

    func logError(_ event: String, req: Request, error: any Error, metadata: [String: String] = [:]) {
        var logMetadata: Logger.Metadata = [
            "audit": "true",
            "event": .string(event),
            "request_id": .string(req.id),
        ]
        for (key, value) in metadata {
            logMetadata[key] = .string(value)
        }
        if let abortError = error as? any AbortError {
            logMetadata["status"] = .string("\(abortError.status.code)")
            logMetadata["reason"] = .string(abortError.reason)
        } else {
            logMetadata["reason"] = .string(String(describing: error))
        }
        logger.warning("\(event)", metadata: logMetadata)
    }
}
