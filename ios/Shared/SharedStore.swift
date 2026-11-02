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
