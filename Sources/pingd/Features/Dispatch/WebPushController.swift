import Vapor

struct WebPushController: RouteCollection {
    let pushProvider: PushProvider

    func boot(routes: any RoutesBuilder) throws {
        let webPush = routes.grouped("webpush")
        webPush.get("vapid-key", use: vapidKey)
    }

    func vapidKey(_ req: Request) async throws -> WebPushOptionsResponse {
        guard let vapidKey = pushProvider.webPushVAPIDKey() else {
            throw Abort(.notFound, reason: "Web Push is not configured")
        }

        return WebPushOptionsResponse(vapid: vapidKey)
    }
}

struct WebPushOptionsResponse: Content {
    let vapid: String
}
