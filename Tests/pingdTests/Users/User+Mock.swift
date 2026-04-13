import Foundation
@testable import pingd

extension User {
    static let vi = User(
        id: UUID(),
        username: "vi",
        passwordHash: "$2b$12$27pKI/uHWjU46JlDqNQBfuwE/y0dhebVwrqC43bNE3b//mYbljqTu", // "password1"
        role: .user
    )
    static let jinx = User(
        id: UUID(),
        username: "jinx",
        passwordHash: "$2b$12$4OZaTaod.xlclKdzlxS5duiTYJDiNp/uQc3Oo.NZRq1MqfnAXFfWK", // "hunter2"
        role: .admin
    )
    static let vander = User(
        id: UUID(),
        username: "vander",
        passwordHash: "$2b$12$FuoGtKBxBqn0ydokERQGyunSLEhfgm1SsdkIfc5OuqPTljzlFsctC", // "letmein"
        role: .user
    )
    static let silco = User(
        id: UUID(),
        username: "silco",
        passwordHash: "$2b$12$2afAgud4.kdGE34H94Ypu.7jPuyh4CL38G5ZF/wNPys3PeVyGYJNi", // "secret123"
        role: .admin
    )
    static let allUsers = [vi, jinx, vander, silco]
}
