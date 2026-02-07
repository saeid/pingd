import Vapor

struct UserController: RouteCollection, @unchecked Sendable {
    let userClient: UserClient

    func boot(routes: any RoutesBuilder) throws {
        let users = routes.grouped("user")
    }
}
