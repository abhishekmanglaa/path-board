import CoreLocation
import MapKit

struct Departure: Codable, Hashable {
    let date: Date
    let headsign: String
    /// Raw feed value: one hex color, or two ("4D92FB,FF9900") for a combined line.
    let lineColors: String

    var line: PathLine { PathLine(feedColors: lineColors, headsign: headsign) }
}

/// Everything the widget and app show: where to go, how long the walk is,
/// and which trains home leave from there.
struct Plan: Codable {
    let stationID: String
    let walkSeconds: TimeInterval
    /// All trains worth showing from the station, soonest first, including ones you can't reach.
    let departures: [Departure]
    let computedAt: Date
    /// Where the walk was measured from, so a nearby later fix can reuse it.
    let originLatitude: Double
    let originLongitude: Double

    var origin: CLLocation { CLLocation(latitude: originLatitude, longitude: originLongitude) }

    var station: Station { Station.byID[stationID] ?? Station.byID[Station.homeID]! }

    /// The walk as shown, rounded up so it errs toward making the train. All the
    /// board's math uses this, so "3 min walk", "train in 8" and "leave in 5" add up.
    var walkMinutes: Int { max(1, Int((walkSeconds / 60).rounded(.up))) }

    /// Trains you can still reach on foot at `now`.
    func catchable(at now: Date) -> [Departure] {
        departures.filter { leaveBy($0) >= now }
    }

    /// Catchable trains split by where they're headed (one group away from home,
    /// WTC and 33rd St at Newport). Groups with nothing listed are kept so the
    /// board layout doesn't jump around.
    func groups(at now: Date) -> [(destination: Destination, trains: [Departure])] {
        let trains = catchable(at: now)
        return station.destinations.map { dest in (dest, trains.filter(dest.includes)) }
    }

    /// The moment you have to start walking to make `departure`.
    func leaveBy(_ departure: Departure) -> Date {
        departure.date.addingTimeInterval(-Double(walkMinutes) * 60)
    }
}

enum PlanError: LocalizedError {
    case feedUnavailable

    var errorDescription: String? { "Couldn't load trains" }
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
        return Plan(stationID: station.id, walkSeconds: walk,
                    departures: try await feed.departures(from: station),
                    computedAt: Date(), originLatitude: here.coordinate.latitude,
                    originLongitude: here.coordinate.longitude)
    }

    /// The closest station by straight line, unless the runner-up is close enough
    /// to plausibly be a shorter walk (the river and rail yards make "closest" and
    /// "quickest" differ) — then both get routed and the shorter walk wins.
    static func candidates(near here: CLLocation) -> [Station] {
        let ranked = Station.all.sorted { $0.location.distance(from: here) < $1.location.distance(from: here) }
        let (d0, d1) = (ranked[0].location.distance(from: here), ranked[1].location.distance(from: here))
        return d1 < d0 * 1.5 + 150 ? [ranked[0], ranked[1]] : [ranked[0]]
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
        return walks.min { $0.1 < $1.1 } ?? (options[0], fallbackWalk(from: here, to: options[0]))
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
                return Departure(date: fetchedAt.addingTimeInterval(seconds), headsign: m.headSign,
                                 lineColors: m.lineColor.uppercased())
            }
            .sorted { $0.date < $1.date }
    }
}
