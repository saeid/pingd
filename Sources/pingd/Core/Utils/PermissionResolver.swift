import Foundation

enum PermissionResolver {

    static func matches(pattern: String, topicName: String) -> Bool {
        if pattern == "*" { return true }
        if pattern.hasSuffix(".>") {
            let prefix = String(pattern.dropLast(2))
            return topicName == prefix || topicName.hasPrefix(prefix + ".")
        }
        if pattern.hasSuffix(".*") {
            let prefix = String(pattern.dropLast(2))
            if topicName == prefix { return true }
            guard topicName.hasPrefix(prefix + ".") else { return false }
            let remainder = topicName.dropFirst(prefix.count + 1)
            return !remainder.contains(".")
        }
        return pattern == topicName
    }

    static func resolve(
        permissions: [Permission],
        topicName: String
    ) -> AccessLevel? {
        let matching = permissions.filter { matches(pattern: $0.topicPattern, topicName: topicName) }
        guard !matching.isEmpty else { return nil }

        // deny always wins
        if matching.contains(where: { $0.accessLevel == .deny }) {
            return .deny
        }
        if matching.contains(where: { $0.accessLevel == .readWrite }) {
            return .readWrite
        }

        let hasRead = matching.contains(where: { $0.accessLevel == .readOnly })
        let hasWrite = matching.contains(where: { $0.accessLevel == .writeOnly })

        if hasRead && hasWrite { return .readWrite }
        if hasRead { return .readOnly }
        if hasWrite { return .writeOnly }

        return nil
    }
}
