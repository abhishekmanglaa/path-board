import CoreLocation
import UIKit
import WidgetKit

@MainActor
final class LocationMonitor: NSObject, ObservableObject {
    static let shared = LocationMonitor()
    @Published private(set) var authorization: CLAuthorizationStatus
    @Published private(set) var plan: Plan?
    @Published private(set) var error: String?
    @Published private(set) var isFarAway = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var selectedStationID: String?
    @Published private(set) var nearbyStations: [Station] = []
    @Published var followsInBackground = SharedStore.followsInBackground

    private let manager = CLLocationManager()
    private let requests = LatestPlanRequest()
    private let poller = ForegroundPoller()
    private var isForeground = false
    private var isFollowing = false
    private var automaticRefresh = AutomaticRefreshGate()
    private var widgetReloads = WidgetReloadGate()

    override private init() {
        authorization = manager.authorizationStatus
        let authorized = [.authorizedAlways, .authorizedWhenInUse].contains(manager.authorizationStatus)
        selectedStationID = SharedStore.selectedStationID ?? (authorized ? nil : Station.homeID)
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 100
        manager.pausesLocationUpdatesAutomatically = true
        plan = SharedStore.plan(for: cacheKey)
        configureBackgroundMonitoring()
    }

    var cacheKey: String { selectedStationID ?? "automatic" }
    var hasAlways: Bool { authorization == .authorizedAlways }
    var hasAnyAccess: Bool { hasAlways || authorization == .authorizedWhenInUse }
    var needsLocation: Bool { selectedStationID == nil && !hasAnyAccess }

    func selectStation(_ id: String?) async {
        requests.cancel()
        selectedStationID = id
        SharedStore.selectedStationID = id
        plan = SharedStore.plan(for: cacheKey)
        error = nil
        isFarAway = false
        if id == nil && !hasAnyAccess {
            isRefreshing = false
            if authorization == .notDetermined { manager.requestWhenInUseAuthorization() }
            return
        }
        await refresh()
    }

    func requestAccess() {
        if authorization == .notDetermined { manager.requestWhenInUseAuthorization() }
        else if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }

    func setBackgroundFollowing(_ enabled: Bool) {
        followsInBackground = enabled
        SharedStore.followsInBackground = enabled
        if enabled {
            switch authorization {
            case .notDetermined: manager.requestWhenInUseAuthorization()
            case .authorizedWhenInUse: manager.requestAlwaysAuthorization()
            default: break
            }
        }
        configureBackgroundMonitoring()
    }

    func refresh(forceFresh: Bool = true, userInitiated: Bool = true) async {
        guard isForeground, !Task.isCancelled else { return }
        let fix = hasAnyAccess ? SharedStore.freshestLocation(manager.location) : nil
        guard selectedStationID != nil || fix != nil else {
            isRefreshing = false
            if hasAnyAccess { manager.requestLocation() }
            return
        }
        await load(from: fix, forceFresh: forceFresh, userInitiated: userInitiated)
    }

    func setForeground(_ active: Bool) {
        isForeground = active
        poller.stop()
        if active {
            automaticRefresh = AutomaticRefreshGate()
            if hasAnyAccess && !isFollowing {
                isFollowing = true
                manager.startUpdatingLocation()
            }
            poller.start(immediately: true, nextInterval: { [weak self] in
                self?.automaticRefresh.delay(lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled) ?? .seconds(30)
            }) { [weak self] in await self?.refresh(userInitiated: false) }
        } else {
            isFollowing = false
            manager.stopUpdatingLocation()
            requests.cancel()
            isRefreshing = false
        }
    }

    private func configureBackgroundMonitoring() {
        // Remove station geofences registered by earlier builds.
        for region in manager.monitoredRegions where Station.byID[region.identifier] != nil {
            manager.stopMonitoring(for: region)
        }
        guard hasAlways && followsInBackground else {
            manager.stopMonitoringSignificantLocationChanges()
            return
        }
        manager.startMonitoringSignificantLocationChanges()
    }

    private func load(from fix: CLLocation?, forceFresh: Bool, userInitiated: Bool = false) async {
        guard isForeground, automaticRefresh.begin(at: Date(), lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled,
                                     userInitiated: userInitiated) else { return }
        let key = cacheKey
        let selected = selectedStationID
        let previous = SharedStore.plan(for: key)
        isRefreshing = true
        do {
            guard let value = try await requests.run({
                try await Planner.plan(from: fix, stationID: selected, previous: previous, forceFresh: forceFresh)
            }) else { return }
            let stationChanged = plan?.stationID != value.stationID
            SharedStore.save(value, for: key)
            plan = value
            error = nil
            isFarAway = false
            isRefreshing = false
            // Planner returns the existing plan unchanged on cache reuse.
            automaticRefresh.succeeded(fetchedNewPlan: value.computedAt != previous?.computedAt)
            reloadWidgets(immediate: userInitiated || stationChanged)
            await CommuteActivityController.shared.update(using: value)
        } catch PlanError.farFromPATH {
            let changed = !isFarAway
            isFarAway = true
            plan = nil
            error = nil
            isRefreshing = false
            reloadWidgets(immediate: userInitiated || changed)
        } catch {
            automaticRefresh.failed()
            self.error = "Couldn't update departures. Check your connection and try again."
            isRefreshing = false
        }
    }

    private func reloadWidgets(immediate: Bool) {
        if widgetReloads.shouldReload(at: Date(), immediate: immediate) {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private func received(_ fix: CLLocation) async {
        guard isForeground || (hasAlways && followsInBackground) else { return }
        guard fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= 200,
              abs(fix.timestamp.timeIntervalSinceNow) <= 300 else { return }
        SharedStore.lastLocation = fix
        // A background location callback only supplies the widget's cached fix.
        guard isForeground else { return }
        nearbyStations = Array(Station.all.sorted { $0.location.distance(from: fix) < $1.location.distance(from: fix) }.prefix(3))
        await load(from: fix, forceFresh: false)
    }
}

extension LocationMonitor: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            let updated = manager.authorizationStatus
            guard updated != authorization else { return }
            authorization = updated
            configureBackgroundMonitoring()
            if followsInBackground && authorization == .authorizedWhenInUse { manager.requestAlwaysAuthorization() }
            setForeground(isForeground || UIApplication.shared.applicationState == .active)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        Task { @MainActor in await received(latest) }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            guard isForeground else { return }
            guard (error as? CLError)?.code != .locationUnknown else { return }
            isRefreshing = false
            if selectedStationID == nil { self.error = "Location unavailable. Choose a station to see departures." }
        }
    }
}
