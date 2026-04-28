import Foundation

enum WebhookTemplateRenderer {
    static func render(_ template: String, json: Any) -> String {
        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: #"\{\{\s*([^}]+?)\s*\}\}"#)
        } catch {
            return template
        }
        let nsTemplate = template as NSString
        let matches = regex.matches(in: template, range: NSRange(location: 0, length: nsTemplate.length))
        var result = template
        for match in matches.reversed() {
            let path = nsTemplate.substring(with: match.range(at: 1))
            let value = resolve(path: path, in: json) ?? ""
            result = (result as NSString).replacingCharacters(in: match.range, with: value)
        }
        return result
    }

    static func splitTags(_ rendered: String) -> [String] {
        rendered
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static func resolve(path: String, in json: Any) -> String? {
        var current: Any? = json
        for key in path.split(separator: ".") {
            guard let dict = current as? [String: Any] else { return nil }
            current = dict[String(key)]
        }
        guard let value = current else { return nil }
        if value is NSNull { return nil }
        if value is [Any] { return nil }
        if value is [String: Any] { return nil }
        if let bool = value as? Bool { return bool ? "true" : "false" }
        return "\(value)"
    }
}
