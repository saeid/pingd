import Foundation
import Vapor

struct RateLimitDecision {
    let isAllowed: Bool
    let retryAfterSeconds: Int?
}

actor RateLimiter {
    private struct FixedWindowState {
        var startedAt: Date
        var count: Int
    }

    private let windowSeconds: Int
    private var windows: [String: FixedWindowState] = [:]

    init(windowSeconds: Int = 60) {
        self.windowSeconds = windowSeconds
    }

    func check(key: String, limit: Int, now: Date) -> RateLimitDecision {
        guard var state = windows[key] else {
            windows[key] = FixedWindowState(startedAt: now, count: 1)
            return RateLimitDecision(isAllowed: true, retryAfterSeconds: nil)
        }

        let elapsedSeconds = Int(now.timeIntervalSince(state.startedAt))
        if elapsedSeconds >= windowSeconds {
            windows[key] = FixedWindowState(startedAt: now, count: 1)
            return RateLimitDecision(isAllowed: true, retryAfterSeconds: nil)
        }

        if state.count >= limit {
            return RateLimitDecision(
                isAllowed: false,
                retryAfterSeconds: max(1, windowSeconds - elapsedSeconds)
            )
        }

        state.count += 1
        windows[key] = state
        return RateLimitDecision(isAllowed: true, retryAfterSeconds: nil)
    }
}

private struct RateLimiterStorageKey: StorageKey {
    typealias Value = RateLimiter
}

extension Application {
    var rateLimiter: RateLimiter {
        get {
            guard let rateLimiter = storage[RateLimiterStorageKey.self] else {
                fatalError("RateLimiter accessed before being configured")
            }
            return rateLimiter
        }
        set {
            storage[RateLimiterStorageKey.self] = newValue
        }
    }
}
