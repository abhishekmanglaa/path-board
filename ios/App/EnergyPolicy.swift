import Foundation

/// The app polls only in the foreground. Manual refresh bypasses this delay.
enum ForegroundRefreshPolicy {
    static func delay(lowPower: Bool, failures: Int) -> Duration {
        let base = lowPower ? 60 : 30
        return .seconds(min(120, base * (1 << min(2, max(0, failures)))))
    }
}

/// One automatic request budget shared by the poller and location callbacks.
/// Reusing a cached plan does not establish that the network has recovered.
struct AutomaticRefreshGate {
    private var lastAttempt: Date?
    private(set) var failures = 0

    func delay(lowPower: Bool) -> Duration {
        ForegroundRefreshPolicy.delay(lowPower: lowPower, failures: failures)
    }

    mutating func begin(at now: Date, lowPower: Bool, userInitiated: Bool) -> Bool {
        if userInitiated { failures = 0 }
        if !userInitiated, let lastAttempt, now >= lastAttempt,
           now.timeIntervalSince(lastAttempt) < Double(delay(lowPower: lowPower).components.seconds) {
            return false
        }
        lastAttempt = now
        return true
    }

    mutating func failed() { failures = min(2, failures + 1) }
    mutating func succeeded(fetchedNewPlan: Bool) {
        if fetchedNewPlan { failures = 0 }
    }
}

/// Saving a plan is cheap; asking WidgetKit to rebuild every timeline is not.
/// Explicit user actions and station changes should still appear immediately.
struct WidgetReloadGate {
    private var lastRequest: Date?

    mutating func shouldReload(at now: Date, immediate: Bool) -> Bool {
        if !immediate, let lastRequest,
           now >= lastRequest, now.timeIntervalSince(lastRequest) < 5 * 60 { return false }
        lastRequest = now
        return true
    }
}
