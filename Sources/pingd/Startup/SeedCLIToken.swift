import Foundation
import Vapor

private var pingdDataDirectory: URL {
    let path = ProcessInfo.processInfo.environment["PINGD_DATA_DIR"] ?? "data"
    return URL(fileURLWithPath: path, isDirectory: true)
}

private var pingdServerURL: String {
    let port = Int(Environment.get("PORT") ?? "") ?? 7685
    return "http://localhost:\(port)"
}

func seedCLIToken(services: AppDependencies, logger: Logger) async throws {
    guard let username = Environment.get("ADMIN_USERNAME"),
          let password = Environment.get("ADMIN_PASSWORD")
    else { return }

    let configFile = pingdDataDirectory.appendingPathComponent("cli-config.json")
    let serverURL = pingdServerURL

    if let data = try? Data(contentsOf: configFile),
       var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       json["token"] as? String != nil {
        let existing = (json["serverURL"] as? String) ?? ""
        if existing != serverURL {
            json["serverURL"] = serverURL
            let updated = try JSONSerialization.data(withJSONObject: json, options: .prettyPrinted)
            try updated.write(to: configFile)
            logger.info("CLI config server URL updated to \(serverURL)")
        } else {
            logger.info("CLI config already exists")
        }
        return
    }

    let user = try await services.authFeature.doBasicAuth(username, password)
    let userID = try user.requireID()
    let token = try await services.tokenClient.createToken(userID, "cli", nil)

    let config: [String: Any] = [
        "serverURL": serverURL,
        "token": token.tokenHash,
    ]
    try FileManager.default.createDirectory(
        at: pingdDataDirectory,
        withIntermediateDirectories: true
    )
    let data = try JSONSerialization.data(
        withJSONObject: config,
        options: .prettyPrinted
    )
    try data.write(to: configFile)

    logger.info("CLI token saved to \(configFile.path)")
}
