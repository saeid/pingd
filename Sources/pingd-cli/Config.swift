import Foundation

struct CLIConfig: Codable {
    var serverURL: String
    var token: String?
}

enum ConfigManager {
    private static let defaultServerURL = "http://localhost:7685"

    private static var dataDir: URL {
        let path = ProcessInfo.processInfo.environment["PINGD_DATA_DIR"] ?? "data"
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private static var configFile: URL {
        dataDir.appendingPathComponent("cli-config.json")
    }

    static func load() -> CLIConfig {
        guard let data = try? Data(contentsOf: configFile),
              let config = try? JSONDecoder().decode(CLIConfig.self, from: data)
        else {
            return CLIConfig(serverURL: defaultServerURL, token: nil)
        }
        return config
    }

    static func save(_ config: CLIConfig) throws {
        try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(config)
        try data.write(to: configFile)
    }
}
