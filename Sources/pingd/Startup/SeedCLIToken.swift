import Foundation
import Vapor

func seedCLIToken(services: AppDependencies, logger: Logger) async throws {
    guard let username = Environment.get("ADMIN_USERNAME"),
          let password = Environment.get("ADMIN_PASSWORD")
    else { return }

    let configDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".pingd")
    let configFile = configDir.appendingPathComponent("config.json")

    if let data = try? Data(contentsOf: configFile),
       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       json["token"] as? String != nil {
        logger.info("CLI config already exists")
        return
    }

    let user = try await services.authFeature.doBasicAuth(username, password)
    let userID = try user.requireID()
    let token = try await services.tokenClient.createToken(userID, "cli", nil)

    try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
    let config: [String: Any] = [
        "serverURL": "http://localhost:8080",
        "token": token.tokenHash,
    ]
    let data = try JSONSerialization.data(withJSONObject: config, options: .prettyPrinted)
    try data.write(to: configFile)

    logger.info("CLI token saved to ~/.pingd/config.json")
}
