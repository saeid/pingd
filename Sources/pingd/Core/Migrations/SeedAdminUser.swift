import Fluent
import Vapor

struct SeedAdminUser: AsyncMigration {
    func prepare(on database: any Database) async throws {
        guard let username = Environment.get("ADMIN_USERNAME"),
              let password = Environment.get("ADMIN_PASSWORD")
        else {
            database.logger.warning("Skipping admin seed — ADMIN_USERNAME and ADMIN_PASSWORD not set")
            return
        }
        let existing = try await User.query(on: database)
            .filter(\.$username == username)
            .first()
        guard existing == nil else {
            database.logger.info("Admin user '\(username)' already exists, skipping seed")
            return
        }
        let hash = try Bcrypt.hash(password)
        let user = User(username: username, passwordHash: hash, role: .admin)
        try await user.save(on: database)
        database.logger.info("Admin user '\(username)' created")
    }

    func revert(on database: any Database) async throws {
        guard let username = Environment.get("ADMIN_USERNAME") else { return }
        try await User.query(on: database)
            .filter(\.$username == username)
            .delete()
    }
}
