import Foundation
import Vapor

enum MessageTagValidator {
    static let maxCount = 10
    static let minLength = 1
    static let maxLength = 30

    private static let allowedCharacters = CharacterSet
        .alphanumerics
        .union(.init(charactersIn: "-_"))

    static func isValid(_ tag: String) -> Bool {
        guard tag.count >= minLength, tag.count <= maxLength else { return false }
        return tag.unicodeScalars.allSatisfy { allowedCharacters.contains($0) }
    }

    static func validate(_ tags: [String]) throws {
        guard tags.count <= maxCount else {
            throw Abort(.badRequest, reason: "Maximum \(maxCount) tags allowed")
        }
        for tag in tags {
            guard tag.count >= minLength, tag.count <= maxLength else {
                throw Abort(.badRequest, reason: "Tag must be \(minLength)-\(maxLength) characters")
            }
            guard tag.unicodeScalars.allSatisfy({ allowedCharacters.contains($0) }) else {
                throw Abort(
                    .badRequest,
                    reason: "Tag '\(tag)' contains invalid characters. Only alphanumeric, dash, underscore allowed"
                )
            }
        }
    }

    static func filter(_ tags: [String]) -> [String] {
        Array(tags.filter(isValid).prefix(maxCount))
    }
}
