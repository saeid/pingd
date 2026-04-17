import Foundation
import Vapor

private func pingdDataDirectory() -> URL {
    let path = ProcessInfo.processInfo.environment["PINGD_DATA_DIR"] ?? "data"
    return URL(fileURLWithPath: path, isDirectory: true)
}

func seedCLIToken(services: AppDependencies, logger: Logger) async throws {
    guard let username = Environment.get("ADMIN_USERNAME"),
          let password = Environment.get("ADMIN_PASSWORD")
    else { return }

    let dataDir = pingdDataDirectory()
    let configFile = dataDir.appendingPathComponent("cli-config.json")

    if let data = try? Data(contentsOf: configFile),
       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       json["token"] as? String != nil {
        logger.info("CLI config already exists")
        return
    }

    let user = try await services.authFeature.doBasicAuth(username, password)
    let userID = try user.requireID()
    let token = try await services.tokenClient.createToken(userID, "cli", nil)

    let config: [String: Any] = [
        "serverURL": "http://localhost:7685",
        "token": token.tokenHash,
    ]
    try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
    let data = try JSONSerialization.data(withJSONObject: config, options: .prettyPrinted)
    try data.write(to: configFile)

    logger.info("CLI token saved to \(configFile.path)")
}
