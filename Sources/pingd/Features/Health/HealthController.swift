import Vapor

struct HealthController: RouteCollection, @unchecked Sendable {
    let healthClient: HealthClient
    let appInfo: AppInfo

    func boot(routes: any RoutesBuilder) throws {
        routes.get("health", use: health)
    }

    func health(_: Request) async throws -> HealthResponse {
        let result = await healthClient.check()
        return HealthResponse(result: result, info: appInfo)
    }
}
