@testable import pingd
import Foundation
import Testing

extension PingdTests {
    @Test("TopicShareFeature: createShare applies defaultShareTokenTTL when expiresAt is nil")
    func shareTokenDefaultTTLApplied() async throws {
        let ownerID = UUID()
        let topicID = UUID()
        let owner = User(id: ownerID, username: "jinx", passwordHash: "x", role: .user)
        let topic = Topic(id: topicID, name: "alpha", ownerUserID: ownerID)
        let frozenNow = Date(timeIntervalSince1970: 1_700_000_000)

        let capturedExpires = ManagedExpiry()

        let feature = TopicShareFeature.live(
            topicShareClient: .mock(
                listForTopic: { _ in [] },
                create: { topicID, hash, label, level, createdBy, expiresAt in
                    await capturedExpires.set(expiresAt)
                    return TopicShareToken(
                        topicID: topicID,
                        tokenHash: hash,
                        label: label,
                        accessLevel: level,
                        createdByUserID: createdBy,
                        expiresAt: expiresAt
                    )
                }
            ),
            topicClient: .mock(getByName: { _ in topic }),
            defaultShareTokenTTL: 3600,
            maxShareTokensPerTopic: nil,
            now: { frozenNow }
        )

        _ = try await feature.createShare(owner, "alpha", nil, .readOnly, nil)
        let captured = await capturedExpires.value
        #expect(captured == frozenNow.addingTimeInterval(3600))
    }

    @Test("TopicShareFeature: createShare honors explicit expiresAt over default TTL")
    func shareTokenExplicitOverridesDefault() async throws {
        let ownerID = UUID()
        let topicID = UUID()
        let owner = User(id: ownerID, username: "jinx", passwordHash: "x", role: .user)
        let topic = Topic(id: topicID, name: "alpha", ownerUserID: ownerID)
        let explicit = Date(timeIntervalSince1970: 1_800_000_000)

        let capturedExpires = ManagedExpiry()

        let feature = TopicShareFeature.live(
            topicShareClient: .mock(
                listForTopic: { _ in [] },
                create: { topicID, hash, label, level, createdBy, expiresAt in
                    await capturedExpires.set(expiresAt)
                    return TopicShareToken(
                        topicID: topicID,
                        tokenHash: hash,
                        label: label,
                        accessLevel: level,
                        createdByUserID: createdBy,
                        expiresAt: expiresAt
                    )
                }
            ),
            topicClient: .mock(getByName: { _ in topic }),
            defaultShareTokenTTL: 3600,
            maxShareTokensPerTopic: nil,
            now: { Date() }
        )

        _ = try await feature.createShare(owner, "alpha", nil, .readOnly, explicit)
        let captured = await capturedExpires.value
        #expect(captured == explicit)
    }

    @Test("TopicShareFeature: createShare rejects when share count meets maxShareTokensPerTopic")
    func shareTokenQuotaEnforced() async throws {
        let ownerID = UUID()
        let topicID = UUID()
        let owner = User(id: ownerID, username: "jinx", passwordHash: "x", role: .user)
        let topic = Topic(id: topicID, name: "alpha", ownerUserID: ownerID)
        let existing = TopicShareToken(
            topicID: topicID,
            tokenHash: "h",
            label: nil,
            accessLevel: .readOnly,
            createdByUserID: ownerID,
            expiresAt: nil
        )

        let feature = TopicShareFeature.live(
            topicShareClient: .mock(
                listForTopic: { _ in [existing, existing] }
            ),
            topicClient: .mock(getByName: { _ in topic }),
            defaultShareTokenTTL: nil,
            maxShareTokensPerTopic: 2,
            now: { Date() }
        )

        await #expect(throws: TopicShareError.self) {
            _ = try await feature.createShare(owner, "alpha", nil, .readOnly, nil)
        }
    }
}

private actor ManagedExpiry {
    private(set) var value: Date?

    func set(_ value: Date?) {
        self.value = value
    }
}
