import CoreLocation
import UIKit
import WidgetKit

/// Keeps the widget following you without the app open.
///
/// With "Always" access, iOS relaunches the app in the background on two kinds of
/// events: significant movement (~500 m, cell-tower based, near-zero battery) and
/// entering/leaving a geofence around each PATH station. Each wakeup stores the
/// new fix for the widget and asks WidgetKit to rebuild its timeline.
@MainActor
final class LocationMonitor: NSObject, ObservableObject {
    static let shared = LocationMonitor()

    @Published private(set) var authorization: CLAuthorizationStatus
    @Published private(set) var plan: Plan?
    @Published private(set) var error: String?
    @Published private(set) var isRefreshing = false

    private let manager = CLLocationManager()
    private static let stationRadius: CLLocationDistance = 300

    override private init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        plan = SharedStore.lastPlan
        startBackgroundMonitoringIfAllowed()
    }

    var hasAlways: Bool { authorization == .authorizedAlways }
    var hasAnyAccess: Bool { hasAlways || authorization == .authorizedWhenInUse }

    func requestAccess() {
        switch authorization {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        // iOS only shows the Always upgrade prompt after When In Use is granted.
        case .authorizedWhenInUse: manager.requestAlwaysAuthorization()
        default:
            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        }
    }

    func refresh() {
        guard hasAnyAccess else { return }
        isRefreshing = true
        manager.requestLocation()
    }

    private func startBackgroundMonitoringIfAllowed() {
        guard hasAlways else { return }
        manager.startMonitoringSignificantLocationChanges()
        let monitored = Set(manager.monitoredRegions.map(\.identifier))
        for station in Station.all where !monitored.contains(station.id) {
            let region = CLCircularRegion(center: station.coordinate, radius: Self.stationRadius, identifier: station.id)
            region.notifyOnEntry = true
            region.notifyOnExit = true
            manager.startMonitoring(for: region)
        }
    }

    private func handle(_ location: CLLocation) async {
        SharedStore.lastLocation = location
        // Background wakeups get ~10s; ask for a little more so the fetch can finish.
        let task = UIApplication.shared.beginBackgroundTask(withName: "plan")
        defer {
            WidgetCenter.shared.reloadAllTimelines()
            UIApplication.shared.endBackgroundTask(task)
            isRefreshing = false
        }
        do {
            let plan = try await Planner.plan(from: location)
            SharedStore.lastPlan = plan
            self.plan = plan
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

extension LocationMonitor: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorization = manager.authorizationStatus
            startBackgroundMonitoringIfAllowed()
            if hasAnyAccess { refresh() }
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        Task { @MainActor in await handle(latest) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        // The geofence event itself is coarse; get a precise fix for the walk time.
        manager.requestLocation()
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        manager.requestLocation()
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            isRefreshing = false
            if (error as? CLError)?.code != .locationUnknown { self.error = "Location unavailable" }
        }
    }
}
