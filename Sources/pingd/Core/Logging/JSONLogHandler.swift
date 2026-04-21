import Foundation
import Logging

struct JSONLogHandler: LogHandler {
    private static let outputLock = NSLock()

    let label: String
    var logLevel: Logger.Level
    var metadataProvider: Logger.MetadataProvider?
    var metadata: Logger.Metadata = [:]

    subscript(metadataKey metadataKey: String) -> Logger.Metadata.Value? {
        get { metadata[metadataKey] }
        set { metadata[metadataKey] = newValue }
    }

    init(
        label: String,
        level: Logger.Level,
        metadataProvider: Logger.MetadataProvider? = LoggingSystem.metadataProvider
    ) {
        self.label = label
        logLevel = level
        self.metadataProvider = metadataProvider
    }

    func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata explicitMetadata: Logger.Metadata?,
        source: String,
        file _: String,
        function _: String,
        line _: UInt
    ) {
        var payload: [String: Any] = [
            "timestamp": Self.timestampString(),
            "level": level.rawValue,
            "label": label,
            "source": source,
            "message": message.description,
        ]

        for (key, value) in effectiveMetadata(explicit: explicitMetadata) {
            guard payload[key] == nil else { continue }
            payload[key] = jsonValue(for: value)
        }

        guard var data = try? JSONSerialization.data(withJSONObject: payload) else {
            return
        }
        data.append(contentsOf: "\n".utf8)
        Self.write(data)
    }

    private func effectiveMetadata(explicit: Logger.Metadata?) -> Logger.Metadata {
        var metadata = metadata

        if let provided = metadataProvider?.get() {
            metadata.merge(provided) { _, new in new }
        }

        if let explicit {
            metadata.merge(explicit) { _, new in new }
        }

        return metadata
    }

    private func jsonValue(for value: Logger.Metadata.Value) -> Any {
        switch value {
        case let .string(string):
            return string
        case let .stringConvertible(convertible):
            return String(describing: convertible)
        case let .dictionary(dictionary):
            return dictionary.mapValues(jsonValue(for:))
        case let .array(array):
            return array.map(jsonValue(for:))
        }
    }

    private static func write(_ data: Data) {
        outputLock.lock()
        defer { outputLock.unlock() }
        FileHandle.standardOutput.write(data)
    }

    private static func timestampString() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: Date())
    }
}
