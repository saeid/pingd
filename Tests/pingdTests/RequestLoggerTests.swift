@testable import pingd
import Testing

extension PingdTests {
    @Test("Request logger redacts /hooks/:token segment")
    func redactHooksToken() {
        #expect(RequestLoggerMiddleware.redact("/hooks/whk_abc123") == "/hooks/:token")
    }

    @Test("Request logger redacts /v1/hooks/:token segment")
    func redactVersionedHooksToken() {
        #expect(RequestLoggerMiddleware.redact("/v1/hooks/whk_abc123") == "/v1/hooks/:token")
    }

    @Test("Request logger leaves non-hook paths unchanged")
    func passthroughNonHookPaths() {
        #expect(RequestLoggerMiddleware.redact("/topics/news/messages") == "/topics/news/messages")
        #expect(RequestLoggerMiddleware.redact("/topics/news/webhooks") == "/topics/news/webhooks")
        #expect(RequestLoggerMiddleware.redact("/auth/login") == "/auth/login")
        #expect(RequestLoggerMiddleware.redact("/") == "/")
    }

    @Test("Request logger leaves bare /hooks unchanged")
    func passthroughBareHooks() {
        #expect(RequestLoggerMiddleware.redact("/hooks") == "/hooks")
        #expect(RequestLoggerMiddleware.redact("/hooks/") == "/hooks/")
    }
}
