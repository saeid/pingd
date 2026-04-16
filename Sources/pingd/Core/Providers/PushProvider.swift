import Vapor

struct PushResult {
    let success: Bool
    let error: String?
}

struct PushProvider {
    let send: @Sendable (_ deviceToken: String, _ pushType: PushType, _ payload: MessagePayload) async throws -> PushResult
}

extension PushProvider {
    static func mock(logger: Logger) -> Self {
        PushProvider(
            send: { deviceToken, pushType, payload in
                logger.info("[PushProvider.mock] \(pushType): \(payload.title ?? "no title") → \(deviceToken)")
                return PushResult(success: true, error: nil)
            }
        )
    }
}
