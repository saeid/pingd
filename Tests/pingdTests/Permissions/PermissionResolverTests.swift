@testable import pingd
import Testing

@Suite("PermissionResolver", .serialized)
struct PermissionResolverTests {

    // MARK: - Pattern Matching

    @Test("PermissionResolver: exact match")
    func exactMatch() {
        #expect(PermissionResolver.matches(pattern: "alerts", topicName: "alerts"))
        #expect(!PermissionResolver.matches(pattern: "alerts", topicName: "alerts.critical"))
        #expect(!PermissionResolver.matches(pattern: "alerts", topicName: "news"))
    }

    @Test("PermissionResolver: global wildcard matches everything")
    func globalWildcard() {
        #expect(PermissionResolver.matches(pattern: "*", topicName: "alerts"))
        #expect(PermissionResolver.matches(pattern: "*", topicName: "alerts.critical"))
        #expect(PermissionResolver.matches(pattern: "*", topicName: "alerts.critical.urgent"))
        #expect(PermissionResolver.matches(pattern: "*", topicName: "news"))
    }

    @Test("PermissionResolver: single-level wildcard .* matches parent and one level deep")
    func singleLevelWildcard() {
        #expect(PermissionResolver.matches(pattern: "alerts.*", topicName: "alerts"))
        #expect(PermissionResolver.matches(pattern: "alerts.*", topicName: "alerts.critical"))
        #expect(PermissionResolver.matches(pattern: "alerts.*", topicName: "alerts.info"))
        #expect(!PermissionResolver.matches(pattern: "alerts.*", topicName: "alerts.critical.urgent"))
        #expect(!PermissionResolver.matches(pattern: "alerts.*", topicName: "news"))
        #expect(!PermissionResolver.matches(pattern: "alerts.*", topicName: "news.breaking"))
    }

    @Test("PermissionResolver: multi-level wildcard .> matches parent and any depth")
    func multiLevelWildcard() {
        #expect(PermissionResolver.matches(pattern: "alerts.>", topicName: "alerts"))
        #expect(PermissionResolver.matches(pattern: "alerts.>", topicName: "alerts.critical"))
        #expect(PermissionResolver.matches(pattern: "alerts.>", topicName: "alerts.critical.urgent"))
        #expect(PermissionResolver.matches(pattern: "alerts.>", topicName: "alerts.critical.urgent.p1"))
        #expect(!PermissionResolver.matches(pattern: "alerts.>", topicName: "news"))
        #expect(!PermissionResolver.matches(pattern: "alerts.>", topicName: "news.breaking"))
    }

    @Test("PermissionResolver: nested prefix patterns")
    func nestedPrefix() {
        #expect(PermissionResolver.matches(pattern: "team.backend.*", topicName: "team.backend"))
        #expect(PermissionResolver.matches(pattern: "team.backend.*", topicName: "team.backend.deploys"))
        #expect(!PermissionResolver.matches(pattern: "team.backend.*", topicName: "team.backend.deploys.prod"))
        #expect(!PermissionResolver.matches(pattern: "team.backend.*", topicName: "team.frontend"))

        #expect(PermissionResolver.matches(pattern: "team.backend.>", topicName: "team.backend"))
        #expect(PermissionResolver.matches(pattern: "team.backend.>", topicName: "team.backend.deploys"))
        #expect(PermissionResolver.matches(pattern: "team.backend.>", topicName: "team.backend.deploys.prod"))
        #expect(!PermissionResolver.matches(pattern: "team.backend.>", topicName: "team.frontend"))
    }

    @Test("PermissionResolver: similar prefixes don't false-match")
    func similarPrefixes() {
        #expect(!PermissionResolver.matches(pattern: "alert.*", topicName: "alerts.critical"))
        #expect(!PermissionResolver.matches(pattern: "alerts.*", topicName: "alertsystem.check"))
        #expect(!PermissionResolver.matches(pattern: "alert.>", topicName: "alerts.critical"))
        #expect(!PermissionResolver.matches(pattern: "alerts.>", topicName: "alertsystem.check"))
    }

    // MARK: - Access Level Resolution

    @Test("PermissionResolver: no matching permissions returns nil")
    func noMatch() {
        let permissions = [
            Permission(scope: .global, accessLevel: .readOnly, userId: nil, topicPattern: "news.*")
        ]
        #expect(PermissionResolver.resolve(permissions: permissions, topicName: "alerts") == nil)
    }

    @Test("PermissionResolver: deny wins on matched topic but not on siblings")
    func denyWins() {
        let permissions = [
            Permission(scope: .global, accessLevel: .readWrite, userId: nil, topicPattern: "alerts.*"),
            Permission(scope: .global, accessLevel: .deny, userId: nil, topicPattern: "alerts.critical")
        ]
        #expect(PermissionResolver.resolve(permissions: permissions, topicName: "alerts.critical") == .deny)
        #expect(PermissionResolver.resolve(permissions: permissions, topicName: "alerts.important") == .readWrite)
    }

    @Test("PermissionResolver: readWrite wins over readOnly and writeOnly")
    func readWriteWins() {
        let permissions = [
            Permission(scope: .global, accessLevel: .readOnly, userId: nil, topicPattern: "alerts.*"),
            Permission(scope: .global, accessLevel: .readWrite, userId: nil, topicPattern: "alerts.>")
        ]
        #expect(PermissionResolver.resolve(permissions: permissions, topicName: "alerts.critical") == .readWrite)
    }

    @Test("PermissionResolver: readOnly + writeOnly combines to readWrite")
    func readPlusWriteCombines() {
        let permissions = [
            Permission(scope: .global, accessLevel: .readOnly, userId: nil, topicPattern: "alerts.*"),
            Permission(scope: .global, accessLevel: .writeOnly, userId: nil, topicPattern: "alerts.>")
        ]
        #expect(PermissionResolver.resolve(permissions: permissions, topicName: "alerts.critical") == .readWrite)
    }

    @Test("PermissionResolver: single readOnly resolves to readOnly")
    func readOnly() {
        let permissions = [
            Permission(scope: .global, accessLevel: .readOnly, userId: nil, topicPattern: "*")
        ]
        #expect(PermissionResolver.resolve(permissions: permissions, topicName: "alerts") == .readOnly)
    }

    @Test("PermissionResolver: single writeOnly resolves to writeOnly")
    func writeOnly() {
        let permissions = [
            Permission(scope: .global, accessLevel: .writeOnly, userId: nil, topicPattern: "*")
        ]
        #expect(PermissionResolver.resolve(permissions: permissions, topicName: "alerts") == .writeOnly)
    }

    @Test("PermissionResolver: deny overrides everything including readWrite")
    func denyOverridesAll() {
        let permissions = [
            Permission(scope: .global, accessLevel: .readWrite, userId: nil, topicPattern: "*"),
            Permission(scope: .global, accessLevel: .readOnly, userId: nil, topicPattern: "secrets.*"),
            Permission(scope: .global, accessLevel: .deny, userId: nil, topicPattern: "secrets.>")
        ]
        #expect(PermissionResolver.resolve(permissions: permissions, topicName: "secrets.keys") == .deny)
        #expect(PermissionResolver.resolve(permissions: permissions, topicName: "alerts") == .readWrite)
    }

    @Test("PermissionResolver: non-matching permissions are ignored in resolution")
    func onlyMatchingCount() {
        let permissions = [
            Permission(scope: .global, accessLevel: .deny, userId: nil, topicPattern: "secrets.*"),
            Permission(scope: .global, accessLevel: .readOnly, userId: nil, topicPattern: "news.*")
        ]
        #expect(PermissionResolver.resolve(permissions: permissions, topicName: "news.breaking") == .readOnly)
    }
}
