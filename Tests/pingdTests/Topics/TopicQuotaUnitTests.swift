@testable import pingd
import Foundation
import Testing

extension PingdTests {
    @Test("TopicFeature: createTopic throws quotaExceeded when count meets max")
    func topicQuotaUnitEnforced() async throws {
        let user = User(id: UUID(), username: "vi", passwordHash: "x", role: .user)
        let feature = TopicFeature.live(
            topicClient: .mock(
                getByName: { _ in nil },
                countForOwner: { _ in 5 },
                create: { _, _, _, _ in
                    Issue.record("Should not call create")
                    return Topic(name: "x", ownerUserID: UUID(), publicRead: false, publicPublish: false)
                }
            ),
            topicShareClient: .mock(),
            permissionClient: .mock(),
            messageClient: .mock(),
            subscriptionClient: .mock(),
            dispatchClient: .mock(),
            reservedTopicNames: [],
            maxTopicsPerUser: 5,
            now: { Date() }
        )

        await #expect(throws: TopicError.self) {
            _ = try await feature.createTopic(user, "new-topic", false, false)
        }
    }

    @Test("TopicFeature: admin bypasses maxTopicsPerUser quota")
    func topicQuotaAdminBypass() async throws {
        let admin = User(id: UUID(), username: "jinx", passwordHash: "x", role: .admin)
        let feature = TopicFeature.live(
            topicClient: .mock(
                getByName: { _ in nil },
                countForOwner: { _ in 100 },
                create: { name, ownerID, publicRead, publicPublish in
                    Topic(name: name, ownerUserID: ownerID, publicRead: publicRead, publicPublish: publicPublish)
                }
            ),
            topicShareClient: .mock(),
            permissionClient: .mock(),
            messageClient: .mock(),
            subscriptionClient: .mock(),
            dispatchClient: .mock(),
            reservedTopicNames: [],
            maxTopicsPerUser: 5,
            now: { Date() }
        )

        let topic = try await feature.createTopic(admin, "admin-topic", false, false)
        #expect(topic.name == "admin-topic")
    }

    @Test("TopicFeature: nil maxTopicsPerUser disables quota")
    func topicQuotaUnlimited() async throws {
        let user = User(id: UUID(), username: "vi", passwordHash: "x", role: .user)
        let feature = TopicFeature.live(
            topicClient: .mock(
                getByName: { _ in nil },
                countForOwner: { _ in 9999 },
                create: { name, ownerID, publicRead, publicPublish in
                    Topic(name: name, ownerUserID: ownerID, publicRead: publicRead, publicPublish: publicPublish)
                }
            ),
            topicShareClient: .mock(),
            permissionClient: .mock(),
            messageClient: .mock(),
            subscriptionClient: .mock(),
            dispatchClient: .mock(),
            reservedTopicNames: [],
            maxTopicsPerUser: nil,
            now: { Date() }
        )

        let topic = try await feature.createTopic(user, "no-limit-topic", false, false)
        #expect(topic.name == "no-limit-topic")
    }
}
