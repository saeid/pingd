import Foundation

struct CLIConfig: Codable {
    var serverURL: String
    var token: String?
}

enum ConfigManager {
    private static var configDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".pingd")
    }

    private static var configFile: URL {
        configDir.appendingPathComponent("config.json")
    }

    static func load() -> CLIConfig {
        guard let data = try? Data(contentsOf: configFile),
              let config = try? JSONDecoder().decode(CLIConfig.self, from: data)
        else {
            return CLIConfig(serverURL: "http://localhost:8080", token: nil)
        }
        return config
    }

    static func save(_ config: CLIConfig) throws {
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(config)
        try data.write(to: configFile)
    }
}
