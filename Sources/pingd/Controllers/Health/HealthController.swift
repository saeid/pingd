import Vapor

struct HealthController: RouteCollection {
    let healthService: HealthService
    let appInfo: AppInfo

    func boot(routes: any RoutesBuilder) throws {
        routes.get("health", use: health)
    }

    func health(_: Request) async throws -> HealthResponse {
        let result = await healthService.check()
        return HealthResponse(result: result, info: appInfo)
    }
}
