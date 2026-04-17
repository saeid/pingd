import Vapor

actor DispatchWorker {
    let dispatchClient: DispatchClient
    let deviceClient: DeviceClient
    let pushProvider: PushProvider
    let messageClient: MessageClient
    let logger: Logger
    let pollInterval: Duration
    let maxRetries: UInt8

    private var isRunning = false
    private var pollTask: Task<Void, Never>?

    init(
        dispatchClient: DispatchClient,
        deviceClient: DeviceClient,
        pushProvider: PushProvider,
        messageClient: MessageClient,
        logger: Logger,
        pollInterval: Duration = .seconds(5),
        maxRetries: UInt8 = 3
    ) {
        self.dispatchClient = dispatchClient
        self.deviceClient = deviceClient
        self.pushProvider = pushProvider
        self.messageClient = messageClient
        self.logger = logger
        self.pollInterval = pollInterval
        self.maxRetries = maxRetries
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        pollTask = Task { await pollLoop() }
    }

    func stop() {
        isRunning = false
        pollTask?.cancel()
        pollTask = nil
    }

    private func pollLoop() async {
        while isRunning && !Task.isCancelled {
            do {
                let pending = try await dispatchClient.fetchPending(50)
                for delivery in pending {
                    guard isRunning, !Task.isCancelled else { break }
                    await processDelivery(delivery)
                }
            } catch {
                guard !Task.isCancelled else { break }
                logger.error("[DispatchWorker] Poll error: \(error)")
            }
            do {
                try await Task.sleep(for: pollInterval)
            } catch {
                break
            }
        }

        isRunning = false
        pollTask = nil
    }

    private func processDelivery(_ delivery: MessageDelivery) async {
        let deliveryID: UUID
        do {
            deliveryID = try delivery.requireID()
        } catch {
            logger.error("[DispatchWorker] Delivery missing ID")
            return
        }

        let deviceID = delivery.$device.id
        let messageID = delivery.$message.id

        do {
            try await dispatchClient.updateStatus(deliveryID, .ongoing, delivery.retryCount)

            guard let device = try await deviceClient.get(deviceID) else {
                logger.warning("[DispatchWorker] Device \(deviceID) not found, marking failed")
                try await dispatchClient.updateStatus(deliveryID, .failed, delivery.retryCount)
                return
            }

            guard let message = try await messageClient.get(messageID) else {
                logger.warning("[DispatchWorker] Message \(messageID) not found, marking failed")
                try await dispatchClient.updateStatus(deliveryID, .failed, delivery.retryCount)
                return
            }

            let result = try await pushProvider.send(device.pushToken, device.pushType, message.payload)

            if result.success {
                try await dispatchClient.updateStatus(deliveryID, .delivered, delivery.retryCount)
            } else {
                let newCount = delivery.retryCount + 1
                if newCount >= maxRetries {
                    logger.warning("[DispatchWorker] Delivery \(deliveryID) max retries, marking failed: \(result.error ?? "unknown")")
                    try await dispatchClient.updateStatus(deliveryID, .failed, newCount)
                } else {
                    logger.info("[DispatchWorker] Delivery \(deliveryID) retry \(newCount)/\(maxRetries): \(result.error ?? "unknown")")
                    try await dispatchClient.updateStatus(deliveryID, .pending, newCount)
                }
            }
        } catch {
            logger.error("[DispatchWorker] Error processing delivery \(deliveryID): \(error)")
            let newCount = delivery.retryCount + 1
            let status: DeliveryStatus = newCount >= maxRetries ? .failed : .pending
            try? await dispatchClient.updateStatus(deliveryID, status, newCount)
        }
    }
}

struct DispatchWorkerLifecycleHandler: LifecycleHandler {
    let worker: DispatchWorker

    func didBootAsync(_ application: Application) async throws {
        await worker.start()
        application.logger.info("Dispatch worker started")
    }

    func shutdownAsync(_ application: Application) async {
        await worker.stop()
        application.logger.info("Dispatch worker stopped")
    }
}
