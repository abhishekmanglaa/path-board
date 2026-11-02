import Foundation

extension Plan {
    /// Widget gallery / placeholder content: 33rd St, a 4 min walk, trains at 8 / 18 / 28.
    static func sample(at now: Date, stationID: String = "33S", walkMinutes: Double = 4,
                       minutes: [Double] = [8, 18, 28], colors: String = "FF9900",
                       headsign: String = "Journal Square") -> Plan {
        let station = Station.byID[stationID]!
        return Plan(stationID: stationID,
                    walkSeconds: walkMinutes * 60,
                    departures: minutes.map { Departure(date: now.addingTimeInterval($0 * 60 + 30), headsign: headsign, lineColors: colors) },
                    computedAt: now,
                    originLatitude: station.latitude, originLongitude: station.longitude)
    }
}

extension Station {
    /// Google Maps walking directions here. The universal link opens the Google
    /// Maps app when it's installed and Google Maps on the web otherwise.
    var googleMapsWalkingURL: URL {
        var c = URLComponents(string: "https://www.google.com/maps/dir/")!
        c.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "destination", value: "\(latitude),\(longitude)"),
            URLQueryItem(name: "travelmode", value: "walking"),
        ]
        return c.url!
    }
}

extension BoardEntry {
    /// Widgets can only open their own app, which forwards to Google Maps.
    var deepLink: URL {
        switch state {
        case .plan(let plan), .failed(_, let plan?):
            return URL(string: "pathhome://walk?station=\(plan.stationID)")!
        default:
            return URL(string: "pathhome://open")!
        }
    }
}
