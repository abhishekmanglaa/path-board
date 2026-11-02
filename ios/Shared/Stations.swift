import CoreLocation

/// A PATH station, keyed by its code in the PANYNJ realtime feed.
struct Station: Hashable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    /// Lowercased headsign fragments of the trains worth showing from here:
    /// trains that stop at Newport, or at Newport itself, trains into New York.
    let shownHeadsigns: [String]
    /// Shown when there's no direct train home from this station.
    let note: String?

    var location: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }
    var coordinate: CLLocationCoordinate2D { location.coordinate }
    var isHome: Bool { id == Station.homeID }

    /// Matches on where the train is going ("Journal Square via Hoboken" goes to
    /// Journal Square), not on any mention of a station in the headsign.
    func shows(_ headsign: String) -> Bool {
        let h = headsign.lowercased()
        return shownHeadsigns.contains { h.hasPrefix($0) }
    }

    /// How the board groups this station's trains. Away from home there's one group
    /// (anything that gets you to Newport); at Newport, one per New York terminal,
    /// the way the RidePATH app lists them.
    var destinations: [Destination] {
        isHome
            ? [Destination(label: "World Trade Center", short: "WTC", match: "world trade"),
               Destination(label: "33rd Street", short: "33rd St", match: "33rd")]
            : [Destination(label: "Newport", short: "Newport", match: nil)]
    }
}

struct Destination: Hashable {
    let label: String
    let short: String
    /// Headsign fragment; nil means every train listed for the station.
    let match: String?

    func includes(_ d: Departure) -> Bool {
        match.map { d.headsign.lowercased().hasPrefix($0) } ?? true
    }
}

extension Station {
    static let homeID = "NEW"

    // Which trains stop at Newport, by line:
    //   HOB–WTC: Hoboken · Newport · Exchange Pl · WTC
    //   JSQ–33:  Journal Sq · Grove · Newport · Christopher … 33rd
    // Overnight JSQ–33 runs via Hoboken; its headsign still contains "journal".
    static let all: [Station] = [
        Station(id: "NWK", name: "Newark", latitude: 40.7347, longitude: -74.1644,
                shownHeadsigns: ["world trade"], note: "Change at Journal Sq"),
        Station(id: "HAR", name: "Harrison", latitude: 40.7393, longitude: -74.1558,
                shownHeadsigns: ["world trade"], note: "Change at Journal Sq"),
        Station(id: "JSQ", name: "Journal Square", latitude: 40.7331, longitude: -74.0628,
                shownHeadsigns: ["33rd"], note: nil),
        Station(id: "GRV", name: "Grove Street", latitude: 40.7197, longitude: -74.0429,
                shownHeadsigns: ["33rd"], note: nil),
        Station(id: "NEW", name: "Newport", latitude: 40.7270, longitude: -74.0337,
                shownHeadsigns: ["world trade", "33rd"], note: nil),
        Station(id: "EXP", name: "Exchange Place", latitude: 40.7163, longitude: -74.0328,
                shownHeadsigns: ["hoboken"], note: nil),
        Station(id: "HOB", name: "Hoboken", latitude: 40.7353, longitude: -74.0291,
                shownHeadsigns: ["world trade", "journal"], note: nil),
        Station(id: "WTC", name: "World Trade Center", latitude: 40.7126, longitude: -74.0099,
                shownHeadsigns: ["hoboken"], note: nil),
        Station(id: "CHR", name: "Christopher Street", latitude: 40.7330, longitude: -74.0071,
                shownHeadsigns: ["journal"], note: nil),
        Station(id: "09S", name: "9th Street", latitude: 40.7342, longitude: -73.9989,
                shownHeadsigns: ["journal"], note: nil),
        Station(id: "14S", name: "14th Street", latitude: 40.7374, longitude: -73.9968,
                shownHeadsigns: ["journal"], note: nil),
        Station(id: "23S", name: "23rd Street", latitude: 40.7429, longitude: -73.9929,
                shownHeadsigns: ["journal"], note: nil),
        Station(id: "33S", name: "33rd Street", latitude: 40.7488, longitude: -73.9884,
                shownHeadsigns: ["journal"], note: nil),
    ]

    static let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
}
