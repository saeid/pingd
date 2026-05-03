import Fluent
@testable import pingd
import Foundation
import Logging
import Testing

@Suite("DispatchWorker", .serialized)
struct DispatchWorkerTests {
    actor StatusCapture {
        private(set) var updates: [(UUID, DeliveryStatus, UInt8)] = []
        func record(_ id: UUID, _ status: DeliveryStatus, _ retry: UInt8) {
            updates.append((id, status, retry))
        }
        func count() -> Int { updates.count }
    }

    actor PendingFeed {
        private var batches: [[MessageDelivery]]
        init(_ batches: [[MessageDelivery]]) { self.batches = batches }
        func next() -> [MessageDelivery] {
            batches.isEmpty ? [] : batches.removeFirst()
        }
    }

    private func makeDelivery(retryCount: UInt8 = 0) -> MessageDelivery {
        MessageDelivery(
            id: UUID(),
            messageId: UUID(),
            deviceId: UUID(),
            status: .pending,
            retryCount: retryCount
        )
    }

    private func makeMessage(expiresAt: Date? = nil, topicName: String = "test-topic") -> Message {
        let message = Message(
            id: UUID(),
            topicID: UUID(),
            time: Date(),
            priority: 3,
            payload: MessagePayload(title: "T", subtitle: nil, body: "B"),
            expiresAt: expiresAt
        )
        message.$topic.value = Topic(name: topicName, ownerUserID: UUID(), visibility: .open)
        return message
    }

    private func makeDevice() -> Device {
        Device(
            id: UUID(),
            userID: UUID(),
            name: "Test",
            platform: .ios,
            pushType: .apns,
            pushToken: "tok"
        )
    }

    private func waitForUpdates(_ capture: StatusCapture, atLeast: Int) async {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if await capture.count() >= atLeast { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    private func run(
        delivery: MessageDelivery,
        device: Device?,
        message: Message?,
        pushResult: PushResult = PushResult(success: true, error: nil),
        maxRetries: UInt8 = 3,
        now: Date = Date()
    ) async -> [(UUID, DeliveryStatus, UInt8)] {
        let capture = StatusCapture()
        let feed = PendingFeed([[delivery]])
        let dispatchClient = DispatchClient.mock(
            fetchPending: { _ in await feed.next() },
            updateStatus: { id, status, retry in
                await capture.record(id, status, retry)
            }
        )
        let deviceClient = DeviceClient.mock(get: { _ in device })
        let messageClient = MessageClient.mock(get: { _ in message })
        let pushProvider = PushProvider(
            webPushVAPIDKey: { nil },
            send: { _, _, _, _, _ in pushResult }
        )
        let worker = DispatchWorker(
            dispatchClient: dispatchClient,
            deviceClient: deviceClient,
            pushProvider: pushProvider,
            messageClient: messageClient,
            logger: Logger(label: "dispatch-worker-test"),
            pollInterval: .milliseconds(10),
            maxRetries: maxRetries,
            now: { now }
        )
        await worker.start()
        await waitForUpdates(capture, atLeast: 2)
        await worker.stop()
        return await capture.updates
    }

    @Test("DispatchWorker: successful push marks delivery delivered")
    func successfulPushMarksDelivered() async throws {
        let delivery = makeDelivery()
        let updates = await run(
            delivery: delivery,
            device: makeDevice(),
            message: makeMessage(),
            pushResult: PushResult(success: true, error: nil)
        )
        let deliveryID = try delivery.requireID()
        #expect(updates.count == 2)
        #expect(updates[0].0 == deliveryID)
        #expect(updates[0].1 == .ongoing)
        #expect(updates[1].1 == .delivered)
        #expect(updates[1].2 == 0)
    }

    @Test("DispatchWorker: push failure under max retries reschedules as pending with bumped retry count")
    func pushFailureRetries() async throws {
        let delivery = makeDelivery(retryCount: 0)
        let updates = await run(
            delivery: delivery,
            device: makeDevice(),
            message: makeMessage(),
            pushResult: PushResult(success: false, error: "transient"),
            maxRetries: 3
        )
        #expect(updates.count == 2)
        #expect(updates[1].1 == .pending)
        #expect(updates[1].2 == 1)
    }

    @Test("DispatchWorker: push failure at max retries marks failed")
    func pushFailureMaxRetries() async throws {
        let delivery = makeDelivery(retryCount: 2)
        let updates = await run(
            delivery: delivery,
            device: makeDevice(),
            message: makeMessage(),
            pushResult: PushResult(success: false, error: "fatal"),
            maxRetries: 3
        )
        #expect(updates.count == 2)
        #expect(updates[1].1 == .failed)
        #expect(updates[1].2 == 3)
    }

    @Test("DispatchWorker: expired message marks delivery expired without sending")
    func expiredMessageMarksExpired() async throws {
        let now = Date()
        let delivery = makeDelivery()
        let updates = await run(
            delivery: delivery,
            device: makeDevice(),
            message: makeMessage(expiresAt: now.addingTimeInterval(-60)),
            pushResult: PushResult(success: true, error: nil),
            now: now
        )
        #expect(updates.count == 2)
        #expect(updates[1].1 == .expired)
    }

    @Test("DispatchWorker: missing device marks delivery failed")
    func missingDeviceMarksFailed() async throws {
        let delivery = makeDelivery(retryCount: 1)
        let updates = await run(
            delivery: delivery,
            device: nil,
            message: makeMessage()
        )
        #expect(updates.count == 2)
        #expect(updates[1].1 == .failed)
        #expect(updates[1].2 == 1)
    }

    @Test("DispatchWorker: missing message marks delivery failed")
    func missingMessageMarksFailed() async throws {
        let delivery = makeDelivery()
        let updates = await run(
            delivery: delivery,
            device: makeDevice(),
            message: nil
        )
        #expect(updates.count == 2)
        #expect(updates[1].1 == .failed)
    }

    @Test("DispatchWorker: stop halts polling")
    func stopHaltsPolling() async throws {
        let capture = StatusCapture()
        let feed = PendingFeed([])
        let dispatchClient = DispatchClient.mock(
            fetchPending: { _ in await feed.next() },
            updateStatus: { id, status, retry in
                await capture.record(id, status, retry)
            }
        )
        let worker = DispatchWorker(
            dispatchClient: dispatchClient,
            deviceClient: DeviceClient.mock(),
            pushProvider: PushProvider(
                webPushVAPIDKey: { nil },
                send: { _, _, _, _, _ in PushResult(success: true, error: nil) }
            ),
            messageClient: MessageClient.mock(),
            logger: Logger(label: "dispatch-worker-test"),
            pollInterval: .milliseconds(10),
            maxRetries: 3,
            now: { Date() }
        )
        await worker.start()
        try await Task.sleep(for: .milliseconds(50))
        await worker.stop()
        #expect(await capture.count() == 0)
    }
}
