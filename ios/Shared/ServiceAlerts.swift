import Foundation

enum ServiceRoute: String, Codable, CaseIterable, Hashable {
    case newarkWTC = "NWK–WTC", hobokenWTC = "HOB–WTC"
    case journalSquare33 = "JSQ–33", hoboken33 = "HOB–33"
    case journalSquare33ViaHoboken = "JSQ–33 via HOB"

    static func routes(for departure: Departure) -> Set<Self> {
        switch departure.line.name {
        case "NWK–WTC": return [.newarkWTC]
        case "HOB–WTC": return [.hobokenWTC]
        case "JSQ–33": return [.journalSquare33]
        case "JSQ–33 via HOB": return [.journalSquare33, .journalSquare33ViaHoboken]
        case "HOB–33": return [.hoboken33]
        default: return []
        }
    }
}

struct ServiceAlert: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let message: String
    let publishedAt: Date
    let routes: Set<ServiceRoute>
    let stationIDs: Set<String>
    let systemWide: Bool

    func applies(to context: ServiceAlertContext) -> Bool {
        systemWide || !routes.isDisjoint(with: context.routes) || !stationIDs.isDisjoint(with: context.stationIDs)
    }

    var scope: String {
        if systemWide { return "PATH" }
        if !routes.isEmpty { return routes.map(\.rawValue).sorted().joined(separator: ", ") }
        return stationIDs.compactMap { Station.byID[$0]?.shortName }.sorted().joined(separator: ", ")
    }
}

/// The commute's routes and places where the rider boards, transfers, or exits.
/// Intermediate station elevator issues don't affect a rider staying on the train.
struct ServiceAlertContext {
    let routes: Set<ServiceRoute>
    let stationIDs: Set<String>

    init(station: Station, destinations: [Destination], departures: [Departure], rowID: String? = nil) {
        var routes = Set(departures.flatMap { ServiceRoute.routes(for: $0) })
        var stations: Set<String> = [station.id, Station.homeID]
        if station.isHome {
            let selected = destinations.filter { rowID == nil || $0.id == rowID }
            for destination in selected {
                if let route: ServiceRoute = ["WTC": .hobokenWTC, "HOB": .hobokenWTC,
                                             "33": .journalSquare33, "JSQ": .journalSquare33][destination.id] {
                    routes.insert(route)
                }
                stations.insert(destination.id == "33" ? "33S" : destination.id)
            }
        } else if rowID == nil {
            // Keep scope even when a suspended service has no live departures.
            switch station.id {
            case "NWK", "HAR": routes.formUnion([.newarkWTC, .journalSquare33]); stations.insert("JSQ")
            case "JSQ", "GRV": routes.insert(.journalSquare33)
            case "WTC", "EXP", "HOB": routes.insert(.hobokenWTC)
            default: routes.formUnion([.journalSquare33, .hoboken33]); stations.insert("HOB")
            }
        } else if routes.contains(.newarkWTC) {
            routes.insert(.journalSquare33); stations.insert("JSQ")
        }
        if routes.contains(.hoboken33) { stations.insert("HOB") }
        self.routes = routes
        stationIDs = stations
    }
}

struct ServiceAlertPresentation {
    let alerts: [ServiceAlert]
    var isStale = false
    var isUnavailable = false

    static let unavailable = Self(alerts: [], isUnavailable: true)
}

struct ServiceAlertSnapshot: Codable, Equatable {
    static let refreshInterval: TimeInterval = 300
    static let validity: TimeInterval = 900
    let fetchedAt: Date
    let alerts: [ServiceAlert]

    func relevant(to context: ServiceAlertContext, at date: Date) -> ServiceAlertPresentation {
        let age = date.timeIntervalSince(fetchedAt)
        guard age >= -5, age < Self.validity else { return .unavailable }
        return ServiceAlertPresentation(alerts: alerts.filter { $0.applies(to: context) },
            isStale: age >= Self.refreshInterval)
    }

    static func decode(_ data: Data, fetchedAt: Date) throws -> Self {
        let decoder = JSONDecoder()
        let records: [Record]
        if let array = try? decoder.decode([Record].self, from: data) { records = array }
        else { records = try decoder.decode(Envelope.self, from: data).data }
        var latest: [String: Record] = [:]
        for record in records {
            guard let date = record.date, date <= fetchedAt.addingTimeInterval(300) else { continue }
            let id = String(record.ebid ?? record.messageid)
            if let previous = latest[id], let oldDate = previous.date,
               oldDate > date || (oldDate == date && previous.messageid > record.messageid) { continue }
            latest[id] = record
        }
        let alerts = latest.compactMap { id, record -> ServiceAlert? in
            guard record.state.lowercased() == "open", let publishedAt = record.date else { return nil }
            let title = Self.clean(record.Subject), message = Self.clean(record.SentMessage)
            guard !title.localizedCaseInsensitiveContains("final update"),
                  !title.localizedCaseInsensitiveContains("back in service"),
                  !title.localizedCaseInsensitiveContains("restored") else { return nil }
            let subjectRoutes = AlertScopeParser.routes(in: title)
            let routes = subjectRoutes.isEmpty ? AlertScopeParser.routes(in: message) : subjectRoutes
            let stations = routes.isEmpty ? AlertScopeParser.stations(in: title) : []
            let systemWide = AlertScopeParser.isSystemWide(title + " " + message)
            guard !routes.isEmpty || !stations.isEmpty || systemWide else { return nil }
            return ServiceAlert(id: id, title: title, message: message, publishedAt: publishedAt,
                routes: routes, stationIDs: stations, systemWide: systemWide)
        }.sorted { ($0.publishedAt, $0.id) > ($1.publishedAt, $1.id) }
        return Self(fetchedAt: fetchedAt, alerts: alerts)
    }

    private struct Envelope: Decodable { let data: [Record] }
    private struct Record: Decodable {
        let ebid: Int64?
        let messageid: Int64
        let sentdate2: String
        let Subject: String
        let SentMessage: String
        let state: String

        var date: Date? {
            guard let milliseconds = sentdate2.components(separatedBy: CharacterSet.decimalDigits.inverted)
                .first(where: { !$0.isEmpty }).flatMap(Double.init), milliseconds.isFinite else { return nil }
            return Date(timeIntervalSince1970: milliseconds / 1000)
        }
    }

    private static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: "<[^>]*>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// The public feed has no structured route IDs. Parse explicit route tokens and
/// the nearest service status, so "JSQ-33 running" never becomes a delay warning.
private enum AlertScopeParser {
    private static let routePatterns: [(ServiceRoute, String)] = [
        (.newarkWTC, #"\b(?:NWK|NEWARK)\s*[-–—]\s*(?:WTC|WORLD TRADE CENTER)\b"#),
        (.hobokenWTC, #"\b(?:HOB|HOBOKEN)\s*[-–—]\s*(?:WTC|WORLD TRADE CENTER)\b"#),
        (.journalSquare33, #"\b(?:JSQ|JOURNAL SQUARE)\s*[-–—]\s*33(?:RD)?(?:\s*ST(?:REET)?)?\b"#),
        (.hoboken33, #"\b(?:HOB|HOBOKEN)\s*[-–—]\s*33(?:RD)?(?:\s*ST(?:REET)?)?\b"#)
    ]
    private static let patterns = routePatterns.map {
        ($0.0, try! NSRegularExpression(pattern: $0.1, options: .caseInsensitive))
    }
    private static let status = try! NSRegularExpression(pattern:
        #"\b(no delays?|not affected|running with (?:residual |minor |major )?delays?|delay\w*|suspend\w*|disrupt\w*|cancel\w*|adjust\w*|clos\w*|construction|not running|out of service|longer waits?|running|normal service|unaffected|restored|resuming|use|take)\b"#,
        options: .caseInsensitive)
    private static let positive: Set<String> = ["running", "normal service", "unaffected", "restored",
                                                "resuming", "use", "take", "not affected", "no delay", "no delays"]

    static func routes(in text: String) -> Set<ServiceRoute> {
        var routes: Set<ServiceRoute> = []
        for sentence in text.components(separatedBy: CharacterSet(charactersIn: ".;\n")) {
            let ns = sentence as NSString
            let range = NSRange(location: 0, length: ns.length)
            let statuses = status.matches(in: sentence, range: range)
            let mentions = patterns.flatMap { route, pattern in
                pattern.matches(in: sentence, range: range).map { (route, $0.range) }
            }.sorted { $0.1.location < $1.1.location }
            for (index, mention) in mentions.enumerated() {
                let (route, token) = mention
                let following = statuses.first { $0.range.location >= NSMaxRange(token) }
                let preceding = statuses.last { NSMaxRange($0.range) <= token.location }
                // An explicit prefix such as "delays on NWK-WTC" belongs to
                // this route, even if a following route is described as normal.
                let previousEnd = index == 0 ? 0 : NSMaxRange(mentions[index - 1].1)
                let prefix = ns.substring(with: NSRange(location: previousEnd, length: token.location - previousEnd))
                let explicitPrefix = prefix.range(of: #"\b(on|to|for|affecting)\s*$"#,
                    options: [.regularExpression, .caseInsensitive]) != nil
                let indicator = explicitPrefix ? preceding ?? following : following ?? preceding
                if let indicator, positive.contains(ns.substring(with: indicator.range).lowercased()) { continue }
                let tail = ns.substring(from: NSMaxRange(token))
                if route == .journalSquare33 && tail.range(of: #"^\s+via\s+(?:HOB|Hoboken)\b"#,
                    options: [.regularExpression, .caseInsensitive]) != nil {
                    routes.insert(.journalSquare33ViaHoboken)
                } else {
                    routes.insert(route)
                }
            }
        }
        return routes
    }

    static func stations(in text: String) -> Set<String> {
        let aliases: [(String, String)] = [
            ("NWK", "NWK|Newark"), ("HAR", "HAR|Harrison"), ("JSQ", "JSQ|Journal (?:Square|Sq)"),
            ("GRV", "GRV|Grove (?:Street|St)"), ("NEW", "Newport"), ("EXP", "Exchange (?:Place|Pl)"),
            ("HOB", "HOB|Hoboken"), ("WTC", "WTC|World Trade Center"), ("CHR", "CHR|Christopher (?:Street|St)"),
            ("09S", "09S|9(?:th)?\\s*(?:Street|St)"), ("14S", "14S|14(?:th)?\\s*(?:Street|St)"),
            ("23S", "23S|23(?:rd)?\\s*(?:Street|St)"), ("33S", "33S|33(?:rd)?\\s*(?:Street|St)")
        ]
        return Set(aliases.compactMap { id, pattern in
            text.range(of: "\\b(?:\(pattern))\\b", options: [.regularExpression, .caseInsensitive]) == nil ? nil : id
        })
    }

    static func isSystemWide(_ text: String) -> Bool {
        text.range(of: #"\b(all PATH(?: lines| routes)?|all lines|all routes|system[- ]wide|entire PATH system)\b"#,
            options: [.regularExpression, .caseInsensitive]) != nil
    }
}

extension Plan {
    func serviceAlertPresentation(at date: Date, showing destinations: [Destination]) -> ServiceAlertPresentation {
        let upcoming = upcoming(at: date)
        let shown = station.isHome ? upcoming.filter { d in destinations.contains { $0.includes(d) } } : upcoming
        let context = ServiceAlertContext(station: station, destinations: destinations, departures: shown)
        return serviceAlerts?.relevant(to: context, at: date) ?? .unavailable
    }
}
