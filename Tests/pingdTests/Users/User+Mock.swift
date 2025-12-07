import Foundation
@testable import pingd

extension User {
    static let vi = User(
        id: UUID(),
        username: "vi",
        passwordHash: "$2b$12$w83jJcJvT0aS0D/8ecjjaa7r0Z10YzZs3uE20vVb/I.SWcFIx2U9C", // "password1"
        role: .user
    )
    static let jinx = User(
        id: UUID(),
        username: "jinx",
        passwordHash: "$2b$12$v2wB9y0q.KH.5jj7DbZBEOuK7GZr6P6uLcxvDyBa7AG6z65PsdRyG", // "hunter2"
        role: .admin
    )
    static let vander = User(
        id: UUID(),
        username: "vander",
        passwordHash: "$2b$12$qTHx8WkE3gs.CFyM3XTj7e43RUfwH2H9XaPq2u7eKZ6C95qz1V/KK", // "letmein"
        role: .user
    )
    static let silco = User(
        id: UUID(),
        username: "silco",
        passwordHash: "$2b$12$Bj6I9cQNfVHB3zAkFH4/ZOLkM3UX4ZzUifjU3Tv1fvFmKCVc9eT5a", // "secret123"
        role: .admin
    )
    static let allUsers = [vi, jinx, vander, silco]
}
