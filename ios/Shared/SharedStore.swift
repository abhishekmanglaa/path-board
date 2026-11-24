import CoreLocation

/// State the app writes and the widget reads, via the shared App Group.
enum SharedStore {
    static let appGroup = "group.com.abhishekmangla.pathhome"
    private static var defaults: UserDefaults { UserDefaults(suiteName: appGroup) ?? .standard }

    /// Last fix the app received, including from background location wakeups.
    /// The widget compares this with its own cached fix and uses the newer one.
    static var lastLocation: CLLocation? {
        get {
            let d = defaults
            guard let ts = d.object(forKey: "loc.ts") as? Double else { return nil }
            return CLLocation(coordinate: CLLocationCoordinate2D(latitude: d.double(forKey: "loc.lat"),
                                                                 longitude: d.double(forKey: "loc.lon")),
                              altitude: 0, horizontalAccuracy: d.double(forKey: "loc.acc"), verticalAccuracy: -1,
                              timestamp: Date(timeIntervalSince1970: ts))
        }
        set {
            let d = defaults
            guard let loc = newValue else { return }
            d.set(loc.coordinate.latitude, forKey: "loc.lat")
            d.set(loc.coordinate.longitude, forKey: "loc.lon")
            d.set(loc.horizontalAccuracy, forKey: "loc.acc")
            d.set(loc.timestamp.timeIntervalSince1970, forKey: "loc.ts")
        }
    }

    /// Last computed plan, so the widget has something to show if a refresh fails.
    static var lastPlan: Plan? {
        get { defaults.data(forKey: "plan").flatMap { try? JSONDecoder().decode(Plan.self, from: $0) } }
        set { defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: "plan") }
    }

    static func plan(for key: String) -> Plan? {
        if key == "automatic" { return lastPlan.flatMap { $0.selectionID == nil ? $0 : nil } }
        return defaults.data(forKey: "plan.\(key)").flatMap { try? JSONDecoder().decode(Plan.self, from: $0) }
    }

    static func save(_ plan: Plan?, for key: String) {
        if key == "automatic" { lastPlan = plan }
        else { defaults.set(plan.flatMap { try? JSONEncoder().encode($0) }, forKey: "plan.\(key)") }
    }

    static var serviceAlerts: ServiceAlertSnapshot? {
        defaults.data(forKey: "path.serviceAlerts")
            .flatMap { try? JSONDecoder().decode(ServiceAlertSnapshot.self, from: $0) }
    }

    static func saveServiceAlerts(_ snapshot: ServiceAlertSnapshot) {
        guard serviceAlerts.map({ $0.fetchedAt < snapshot.fetchedAt }) ?? true,
              let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: "path.serviceAlerts")
    }

    static var selectedStationID: String? {
        get { defaults.string(forKey: "station.selected").flatMap { Station.byID[$0] == nil ? nil : $0 } }
        set { defaults.set(newValue, forKey: "station.selected") }
    }

    static var pinnedStationIDs: [String] {
        get { (defaults.stringArray(forKey: "station.pinned") ?? ["NEW", "33S", "WTC"]).filter { Station.byID[$0] != nil } }
        set { defaults.set(newValue, forKey: "station.pinned") }
    }

    static var bufferMinutes: Int {
        get { min(3, max(1, (defaults.object(forKey: "station.buffer") as? Int) ?? 2)) }
        set { defaults.set(min(3, max(1, newValue)), forKey: "station.buffer") }
    }

    static var followsInBackground: Bool {
        get { defaults.bool(forKey: "location.background") }
        set { defaults.set(newValue, forKey: "location.background") }
    }

    /// Which directions the board shows at Newport, in the app's settings.
    static var newportDestinationIDs: [String] {
        get { defaults.stringArray(forKey: "newport.destinations") ?? Destination.defaultNewportIDs }
        set { defaults.set(newValue, forKey: "newport.destinations") }
    }

    static var newportDestinations: [Destination] {
        let ids = newportDestinationIDs
        return Destination.newport.filter { ids.contains($0.id) }
    }

    /// Whichever fix is newer: one the widget can read directly, or one the app stored.
    static func freshestLocation(_ candidates: CLLocation?...) -> CLLocation? {
        (candidates + [lastLocation]).compactMap { $0 }.max { $0.timestamp < $1.timestamp }
    }
}
