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
            let segment = String(key)
            if let dict = current as? [String: Any] {
                current = dict[segment]
            } else if let array = current as? [Any], let index = Int(segment), array.indices.contains(index) {
                current = array[index]
            } else {
                return nil
            }
        }
        return renderScalar(current)
    }

    private static func renderScalar(_ value: Any?) -> String? {
        guard let value else { return nil }
        if value is NSNull { return nil }
        if let array = value as? [Any] { return renderArray(array) }
        if value is [String: Any] { return nil }
        if let bool = value as? Bool { return bool ? "true" : "false" }
        if let number = value as? NSNumber { return formatNumber(number) }
        return "\(value)"
    }

    private static func renderArray(_ array: [Any]) -> String {
        array.compactMap { element -> String? in
            if element is NSNull { return nil }
            if element is [Any] { return nil }
            if element is [String: Any] { return nil }
            if let bool = element as? Bool { return bool ? "true" : "false" }
            if let number = element as? NSNumber { return formatNumber(number) }
            return "\(element)"
        }.joined(separator: ", ")
    }

    private static func formatNumber(_ number: NSNumber) -> String {
        let double = number.doubleValue
        if double.truncatingRemainder(dividingBy: 1) == 0,
           double >= Double(Int64.min),
           double <= Double(Int64.max) {
            return String(Int64(double))
        }
        return "\(number)"
    }
}
