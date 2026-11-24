import CoreLocation

/// Scheduled timelines use cached location. A manual refresh can ask for one fix.
@MainActor
final class WidgetPlanRefresh: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var pending: CheckedContinuation<CLLocation?, Never>?
    private var timeout: Task<Void, Never>?

    static func load(options: WidgetOptions, forceFresh: Bool = false) async throws -> Plan? {
        let location = WidgetPlanRefresh()
        let authorized = location.manager.isAuthorizedForWidgetUpdates
        let previous = SharedStore.plan(for: options.cacheKey)
        let cached = authorized ? SharedStore.freshestLocation(location.manager.location) : nil
        let fix = authorized ? await resolveFix(
            cached: cached, requestIfNeeded: forceFresh, at: .now, request: location.requestFix
        ) : nil
        if let fix, SharedStore.lastLocation.map({ $0.timestamp < fix.timestamp }) ?? true {
            SharedStore.lastLocation = fix
        }
        let now = Date()
        let useSaved = authorized && canUseSavedLocation(previous: previous, latestFix: fix ?? cached, at: now)
        guard options.stationID != nil || fix != nil || useSaved else { return nil }
        let plan = try await Planner.plan(from: fix, stationID: options.stationID, previous: previous,
            now: now, forceFresh: forceFresh, allowSavedLocation: useSaved)
        SharedStore.save(plan, for: options.cacheKey)
        return plan
    }

    static func resolveFix(cached: CLLocation?, requestIfNeeded: Bool, at now: Date,
                           request: () async -> CLLocation?) async -> CLLocation? {
        if let cached, usable(cached, at: now) { return cached }
        guard requestIfNeeded, !Task.isCancelled else { return nil }
        return await request()
    }

    static func canUseSavedLocation(previous: Plan?, latestFix: CLLocation?, at now: Date) -> Bool {
        guard let previous, previous.hasDisplayWalk(at: now) else { return false }
        // A newer fix can rule out the old station even after it is too old
        // to give a new walking estimate.
        guard let latestFix, latestFix.timestamp > previous.walkMeasuredAt,
              latestFix.timestamp.timeIntervalSince(now) <= 5,
              (0...200).contains(latestFix.horizontalAccuracy) else { return true }
        let tolerance = max(Planner.sameSpotMeters, latestFix.horizontalAccuracy)
        return latestFix.distance(from: previous.origin) < tolerance
    }

    private func requestFix() async -> CLLocation? {
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.delegate = self
        return await withCheckedContinuation { continuation in
            pending = continuation
            timeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
                self?.finish(nil)
            }
            manager.requestLocation()
        }
    }

    private static func usable(_ location: CLLocation, at now: Date) -> Bool {
        let age = now.timeIntervalSince(location.timestamp)
        return age >= -5 && age <= Plan.walkAdviceAge
            && location.horizontalAccuracy >= 0 && location.horizontalAccuracy <= 200
    }

    private func finish(_ fix: CLLocation?) {
        guard let pending else { return }
        self.pending = nil
        timeout?.cancel()
        timeout = nil
        manager.stopUpdatingLocation()
        pending.resume(returning: fix)
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in finish(locations.last { Self.usable($0, at: .now) }) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in finish(nil) }
    }
}
