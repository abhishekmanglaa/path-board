import CoreLocation
import MapKit

struct Departure: Codable, Hashable {
    let date: Date
    let headsign: String
    /// Raw feed value: one hex color, or two ("4D92FB,FF9900") for a combined line.
    let lineColors: String
    /// From Newport's timetable rather than posted by PATH.
    var scheduled = false

    var line: PathLine { PathLine(feedColors: lineColors, headsign: headsign) }
}

extension Departure {
    private enum CodingKeys: String, CodingKey { case date, headsign, lineColors, scheduled }

    /// Plans saved before `scheduled` existed still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(Date.self, forKey: .date)
        headsign = try c.decode(String.self, forKey: .headsign)
        lineColors = try c.decode(String.self, forKey: .lineColors)
        scheduled = try c.decodeIfPresent(Bool.self, forKey: .scheduled) ?? false
    }
}

/// Everything the widget and app show: where to go, how long the walk is,
/// and which trains home leave from there.
struct Plan: Codable {
    let stationID: String
    let walkSeconds: TimeInterval
    /// All trains worth showing from the station, soonest first: the ones PATH has
    /// posted and, at Newport, the timetabled ones after them.
    let departures: [Departure]
    let computedAt: Date
    /// Where the walk was measured from, so a nearby later fix can reuse it.
    let originLatitude: Double
    let originLongitude: Double

    var origin: CLLocation { CLLocation(latitude: originLatitude, longitude: originLongitude) }

    var station: Station { Station.byID[stationID] ?? Station.byID[Station.homeID]! }

    /// The walk as shown, rounded up so it never understates how far it is.
    var walkMinutes: Int { max(1, Int((walkSeconds / 60).rounded(.up))) }

    /// Trains that haven't left yet, soonest first.
    func upcoming(at now: Date) -> [Departure] {
        departures.filter { $0.date > now }
    }
}

enum PlanError: LocalizedError, Equatable {
    case feedUnavailable
    /// Nowhere near PATH: no station is a sensible walk away.
    case farFromPATH

    var errorDescription: String? {
        switch self {
        case .feedUnavailable: return "Couldn't load trains"
        case .farFromPATH: return "No PATH station within walking distance"
        }
    }
}

enum Planner {
    private static let feedURL = URL(string: "https://www.panynj.gov/bin/portauthority/ridepath.json")!

    /// A fix this close to the last plan's origin gives the same walk.
    static let sameSpotMeters: CLLocationDistance = 75
    /// A plan this fresh from the same spot is reused outright — typically the app
    /// just computed it and asked the widget to reload.
    static let reuseWindow: TimeInterval = 60

    /// `forceFresh` (a refresh tap) always refetches trains, but still reuses the
    /// walk when you haven't moved.
    static func plan(from here: CLLocation, previous: Plan? = SharedStore.lastPlan, now: Date = Date(),
                     forceFresh: Bool = false) async throws -> Plan {
        guard isNearPATH(here) else { throw PlanError.farFromPATH }
        let sameSpot = previous.map { $0.origin.distance(from: here) < sameSpotMeters } ?? false
        if let previous, sameSpot, !forceFresh, now.timeIntervalSince(previous.computedAt) < reuseWindow {
            return previous
        }

        async let feed = fetchFeed()
        let (station, walk): (Station, TimeInterval)
        if let previous, sameSpot {
            // Haven't moved: the walk is unchanged, only the trains need refreshing.
            (station, walk) = (previous.station, previous.walkSeconds)
        } else {
            (station, walk) = await nearestByWalk(from: here)
        }
        let fetched = try await feed
        return Plan(stationID: station.id, walkSeconds: walk,
                    departures: withTimetable(fetched.departures(from: station), at: station, now: fetched.fetchedAt),
                    computedAt: Date(), originLatitude: here.coordinate.latitude,
                    originLongitude: here.coordinate.longitude)
    }

    /// At Newport, PATH posts about one train per direction; the timetable fills in
    /// the ones after it. Other stations have no timetable and show only live trains.
    static func withTimetable(_ live: [Departure], at station: Station, now: Date) -> [Departure] {
        guard station.isHome else { return live }
        let scheduled = station.destinations.flatMap { dest -> [Departure] in
            let posted = live.filter(dest.includes)
            // Scheduled trains look like the posted one (it may be the overnight via-Hoboken run).
            let like = posted.last
            return NewportSchedule.projected(dest.id, after: posted.map(\.date), now: now).map {
                Departure(date: $0, headsign: like?.headsign ?? dest.headsign,
                          lineColors: like?.lineColors ?? dest.lineColors, scheduled: true)
            }
        }
        return (live + scheduled).sorted { $0.date < $1.date }
    }

    /// Farther than this from every station (about an hour's walk), there's no
    /// sensible station to show.
    static let walkableMeters: CLLocationDistance = 4000
    /// Newport is in reach on foot from this far; walking home may beat a train.
    static let homeWalkMeters: CLLocationDistance = 1500
    /// Walking to Newport wins unless another station saves at least this much walk,
    /// roughly the wait plus the one-stop ride back to Newport it would cost:
    /// between Newport and Exchange Place you walk home, not to a train back to it.
    static let homeBias: TimeInterval = 6 * 60

    static func isNearPATH(_ here: CLLocation) -> Bool {
        Station.all.contains { $0.location.distance(from: here) <= walkableMeters }
    }

    /// The closest station by straight line, unless the runner-up is close enough
    /// to plausibly be a shorter walk (the river and rail yards make "closest" and
    /// "quickest" differ) — then both get routed and the shorter walk wins. Newport
    /// is routed too whenever it's walkable.
    static func candidates(near here: CLLocation) -> [Station] {
        let ranked = Station.all.sorted { $0.location.distance(from: here) < $1.location.distance(from: here) }
        let (d0, d1) = (ranked[0].location.distance(from: here), ranked[1].location.distance(from: here))
        var out = d1 < d0 * 1.5 + 150 ? [ranked[0], ranked[1]] : [ranked[0]]
        let home = Station.byID[Station.homeID]!
        if !out.contains(home), home.location.distance(from: here) <= homeWalkMeters { out.append(home) }
        return out
    }

    /// The shortest walk, except that Newport keeps the tie unless another
    /// station is `homeBias` closer.
    static func choose(_ walks: [(Station, TimeInterval)]) -> (Station, TimeInterval)? {
        guard let best = walks.min(by: { $0.1 < $1.1 }) else { return nil }
        if let home = walks.first(where: { $0.0.isHome }), home.1 <= best.1 + homeBias { return home }
        return best
    }

    private static func nearestByWalk(from here: CLLocation) async -> (Station, TimeInterval) {
        let options = candidates(near: here)
        let walks = await withTaskGroup(of: (Station, TimeInterval).self) { group in
            for station in options {
                group.addTask { (station, await walkSeconds(from: here, to: station)) }
            }
            var out: [(Station, TimeInterval)] = []
            for await result in group { out.append(result) }
            return out
        }
        return choose(walks) ?? (options[0], fallbackWalk(from: here, to: options[0]))
    }

    /// Apple Maps walking ETA; straight-line estimate if MapKit can't route.
    static func walkSeconds(from here: CLLocation, to station: Station) async -> TimeInterval {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: here.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: station.coordinate))
        request.transportType = .walking
        if let eta = try? await MKDirections(request: request).calculateETA() {
            return eta.expectedTravelTime
        }
        return fallbackWalk(from: here, to: station)
    }

    /// Street grid detour ≈ 1.3×, walking pace ≈ 1.35 m/s.
    static func fallbackWalk(from here: CLLocation, to station: Station) -> TimeInterval {
        station.location.distance(from: here) * 1.3 / 1.35
    }

    /// No disk cache, no cookies: the feed is always fetched fresh and widget
    /// extensions have a tight memory budget.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 10
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    private static func fetchFeed() async throws -> PathFeed {
        var request = URLRequest(url: feedURL)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw PlanError.feedUnavailable }
        return try PathFeed(data: data, fetchedAt: Date())
    }
}

/// PANYNJ realtime feed: one entry per station, each with upcoming trains per direction.
struct PathFeed {
    struct Body: Decodable { let results: [Result] }
    struct Result: Decodable {
        let consideredStation: String
        let destinations: [Destination]
    }
    struct Destination: Decodable { let messages: [Message] }
    struct Message: Decodable {
        let secondsToArrival: String
        let headSign: String
        let lineColor: String
        /// When PATH computed `secondsToArrival`; often a minute before we fetch.
        let lastUpdated: String?
    }

    let fetchedAt: Date
    let body: Body

    init(data: Data, fetchedAt: Date) throws {
        self.fetchedAt = fetchedAt
        body = try JSONDecoder().decode(Body.self, from: data)
    }

    func departures(from station: Station) -> [Departure] {
        guard let result = body.results.first(where: { $0.consideredStation == station.id }) else { return [] }
        return result.destinations
            .flatMap(\.messages)
            .filter { station.shows($0.headSign) }
            .compactMap { m in
                guard let seconds = Double(m.secondsToArrival) else { return nil }
                return Departure(date: Self.postedAt(m.lastUpdated, fetchedAt: fetchedAt).addingTimeInterval(seconds),
                                 headsign: m.headSign,
                                 lineColors: m.lineColor.uppercased())
            }
            .sorted { $0.date < $1.date }
    }

    /// Counts are measured from when PATH posted them, not from our fetch, so they
    /// match the RidePATH app instead of reading up to a minute high. Falls back
    /// to the fetch time if the stamp is missing or implausible.
    static func postedAt(_ stamp: String?, fetchedAt: Date) -> Date {
        guard let stamp, let posted = parseStamp(stamp),
              posted <= fetchedAt.addingTimeInterval(5), posted > fetchedAt.addingTimeInterval(-600) else { return fetchedAt }
        return posted
    }

    /// "2026-11-02T14:49:42.949787-05:00": ISO 8601 with microseconds, which
    /// ISO8601DateFormatter won't parse, so the fraction is added separately.
    static func parseStamp(_ s: String) -> Date? {
        let pattern = #/^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(\.\d+)?(Z|[+-]\d{2}:\d{2})$/#
        guard let m = s.wholeMatch(of: pattern),
              let base = ISO8601DateFormatter().date(from: String(m.1) + String(m.3)) else { return nil }
        return base.addingTimeInterval(m.2.flatMap { Double("0" + $0) } ?? 0)
    }
}
