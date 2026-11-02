import CoreLocation

/// A PATH station, keyed by its code in the PANYNJ realtime feed.
struct Station: Hashable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    /// Lowercased headsign fragments of the trains worth showing from here:
    /// trains that get you home (stopping at Newport, or at Hoboken one stop
    /// short of it), or at Newport itself, every direction.
    let shownHeadsigns: [String]
    /// Shown when there's no direct train home from this station.
    let note: String?
    /// How this station's trains toward Newport line up with Newport's timetable.
    var timetable: Leg? = nil

    /// A line through this station and Newport: its trains leave here about
    /// `minutesBefore` minutes before they leave Newport toward `newport` (whose
    /// headsign they share). The live train corrects any error in the estimate.
    struct Leg: Hashable {
        let newport: String
        let minutesBefore: Double

        var destination: Destination { Destination.newport.first { $0.id == newport }! }
    }

    var location: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }
    var coordinate: CLLocationCoordinate2D { location.coordinate }
    var isHome: Bool { id == Station.homeID }

    /// Matches on where the train is going ("Journal Square via Hoboken" goes to
    /// Journal Square), not on any mention of a station in the headsign.
    func shows(_ headsign: String) -> Bool {
        let h = headsign.lowercased()
        return shownHeadsigns.contains { h.hasPrefix($0) }
    }

    /// The directions the board can show from here. Away from home there's one
    /// (anything that gets you to Newport); at Newport, each terminal, the way the
    /// RidePATH app lists them. Which of those appear is a setting.
    var destinations: [Destination] { isHome ? Destination.newport : [Destination.toNewport] }
}

struct Destination: Hashable, Identifiable {
    /// Also the key into Newport's timetable.
    let id: String
    let label: String
    let short: String
    /// For the small widget's narrow rows.
    let tiny: String
    /// Headsign prefix; nil means every train listed for the station.
    let match: String?
    /// What a scheduled train in this direction looks like before any are posted.
    let headsign: String
    let lineColors: String

    func includes(_ d: Departure) -> Bool {
        match.map { d.headsign.lowercased().hasPrefix($0) } ?? true
    }

    static let newport: [Destination] = [
        Destination(id: "WTC", label: "World Trade Center", short: "WTC", tiny: "WTC",
                    match: "world trade", headsign: "World Trade Center", lineColors: "65C100"),
        Destination(id: "33", label: "33rd Street", short: "33rd St", tiny: "33rd",
                    match: "33rd", headsign: "33rd Street", lineColors: "FF9900"),
        Destination(id: "JSQ", label: "Journal Square", short: "Journal Sq", tiny: "JSQ",
                    match: "journal", headsign: "Journal Square", lineColors: "FF9900"),
        Destination(id: "HOB", label: "Hoboken", short: "Hoboken", tiny: "HOB",
                    match: "hoboken", headsign: "Hoboken", lineColors: "65C100"),
    ]
    static let defaultNewportIDs = ["WTC", "33", "JSQ"]
    static let toNewport = Destination(id: "home", label: "Newport", short: "Newport", tiny: "Newport",
                                       match: nil, headsign: "", lineColors: "")
}

extension Station {
    static let homeID = "NEW"

    // Which trains get you home, by line:
    //   HOB–WTC: Hoboken · Newport · Exchange Pl · WTC
    //   JSQ–33:  Journal Sq · Grove · Newport · Christopher … 33rd
    //   HOB–33:  Hoboken · Christopher … 33rd — one stop or a walk short of Newport
    // Overnight JSQ–33 runs via Hoboken; its headsign still contains "journal".
    // Journal Sq-bound minutes before Newport, measured from the live feed.
    private static func nyLeg(_ minutesBefore: Double) -> Leg {
        Leg(newport: "JSQ", minutesBefore: minutesBefore)
    }

    // Coordinates are where Apple Maps puts each station, so walks route to the
    // entrance rather than to a point it can only reach the long way round.
    static let all: [Station] = [
        Station(id: "NWK", name: "Newark", latitude: 40.7340, longitude: -74.1645,
                shownHeadsigns: ["world trade"], note: "Change at Journal Sq"),
        Station(id: "HAR", name: "Harrison", latitude: 40.7393, longitude: -74.1558,
                shownHeadsigns: ["world trade"], note: "Change at Journal Sq"),
        Station(id: "JSQ", name: "Journal Square", latitude: 40.7323, longitude: -74.0629,
                shownHeadsigns: ["33rd"], note: nil, timetable: Leg(newport: "33", minutesBefore: 7)),
        Station(id: "GRV", name: "Grove Street", latitude: 40.7192, longitude: -74.0420,
                shownHeadsigns: ["33rd"], note: nil, timetable: Leg(newport: "33", minutesBefore: 3)),
        Station(id: "NEW", name: "Newport", latitude: 40.7268, longitude: -74.0348,
                shownHeadsigns: ["world trade", "33rd", "journal", "hoboken"], note: nil),
        Station(id: "EXP", name: "Exchange Place", latitude: 40.7168, longitude: -74.0324,
                shownHeadsigns: ["hoboken"], note: nil, timetable: Leg(newport: "HOB", minutesBefore: 3)),
        Station(id: "HOB", name: "Hoboken", latitude: 40.7353, longitude: -74.0291,
                shownHeadsigns: ["world trade", "journal"], note: nil,
                timetable: Leg(newport: "WTC", minutesBefore: 4)),
        Station(id: "WTC", name: "World Trade Center", latitude: 40.7126, longitude: -74.0099,
                shownHeadsigns: ["hoboken"], note: nil, timetable: Leg(newport: "HOB", minutesBefore: 7)),
        Station(id: "CHR", name: "Christopher Street", latitude: 40.7330, longitude: -74.0071,
                shownHeadsigns: ["journal", "hoboken"], note: nil, timetable: nyLeg(5)),
        Station(id: "09S", name: "9th Street", latitude: 40.7342, longitude: -73.9989,
                shownHeadsigns: ["journal", "hoboken"], note: nil, timetable: nyLeg(6.5)),
        Station(id: "14S", name: "14th Street", latitude: 40.7374, longitude: -73.9968,
                shownHeadsigns: ["journal", "hoboken"], note: nil, timetable: nyLeg(8)),
        Station(id: "23S", name: "23rd Street", latitude: 40.7429, longitude: -73.9929,
                shownHeadsigns: ["journal", "hoboken"], note: nil, timetable: nyLeg(9.5)),
        Station(id: "33S", name: "33rd Street", latitude: 40.7488, longitude: -73.9884,
                shownHeadsigns: ["journal", "hoboken"], note: nil, timetable: nyLeg(11)),
    ]

    static let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
}
