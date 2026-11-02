import CoreLocation
import SwiftUI
import XCTest
@testable import PathHome

final class FeedTests: XCTestCase {
    /// Every (headsign, color) the live feed uses, offered at every station, in both directions.
    private func fixture(at stations: [String] = Station.all.map(\.id)) -> Data {
        let messages: [[String: String]] = [
            ("World Trade Center", "65C100", 120), ("World Trade Center", "D93A30", 200),
            ("33rd Street", "FF9900", 300), ("33rd Street", "4D92FB", 400),
            ("Hoboken", "65C100", 500), ("Hoboken", "4D92FB", 600),
            ("Journal Square", "FF9900", 700), ("Journal Square via Hoboken", "4D92FB,FF9900", 800),
            ("Newark", "D93A30", 900),
        ].map { ["headSign": $0.0, "lineColor": $0.1, "secondsToArrival": String($0.2), "target": "X"] }
        let results = stations.map { ["consideredStation": $0, "destinations": [["label": "ToNY", "messages": messages]]] as [String: Any] }
        return try! JSONSerialization.data(withJSONObject: ["results": results])
    }

    private func shownHeadsigns(at id: String) throws -> Set<String> {
        let feed = try PathFeed(data: fixture(), fetchedAt: Date())
        return Set(feed.departures(from: Station.byID[id]!).map(\.headsign))
    }

    func testOnlyTrainsThatStopAtNewport() throws {
        // From the NY side and Christopher St: JSQ–33 trains (incl. overnight via Hoboken), never HOB–33.
        for id in ["33S", "23S", "14S", "09S", "CHR"] {
            XCTAssertEqual(try shownHeadsigns(at: id), ["Journal Square", "Journal Square via Hoboken"], id)
        }
        // Downtown: the Hoboken-bound HOB–WTC train, not the Newark one.
        XCTAssertEqual(try shownHeadsigns(at: "WTC"), ["Hoboken"])
        XCTAssertEqual(try shownHeadsigns(at: "EXP"), ["Hoboken"])
        // Grove / JSQ: 33rd-bound JSQ–33 passes Newport; WTC-bound trains don't.
        XCTAssertEqual(try shownHeadsigns(at: "GRV"), ["33rd Street"])
        XCTAssertEqual(try shownHeadsigns(at: "JSQ"), ["33rd Street"])
        // Hoboken: the WTC-bound HOB–WTC train stops at Newport next.
        XCTAssertTrue(try shownHeadsigns(at: "HOB").contains("World Trade Center"))
        XCTAssertFalse(try shownHeadsigns(at: "HOB").contains("33rd Street"))
        XCTAssertEqual(try shownHeadsigns(at: "NEW"), ["World Trade Center", "33rd Street"])
    }

    func testDeparturesAreDatedAndSorted() throws {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let feed = try PathFeed(data: fixture(), fetchedAt: t0)
        let deps = feed.departures(from: Station.byID["33S"]!)
        XCTAssertEqual(deps.map { $0.date.timeIntervalSince(t0) }, [700, 800])
        XCTAssertEqual(deps.last?.line.name, "JSQ–33 via HOB")
    }

    func testBadSecondsAreSkipped() throws {
        let json = #"{"results":[{"consideredStation":"WTC","destinations":[{"label":"ToNJ","messages":[{"headSign":"Hoboken","lineColor":"65C100","secondsToArrival":"","target":"HOB"},{"headSign":"Hoboken","lineColor":"65C100","secondsToArrival":"90","target":"HOB"}]}]}]}"#
        let deps = try PathFeed(data: Data(json.utf8), fetchedAt: Date()).departures(from: Station.byID["WTC"]!)
        XCTAssertEqual(deps.count, 1)
    }

    func testMissingStationGivesNoTrainsNotACrash() throws {
        let feed = try PathFeed(data: fixture(at: ["WTC"]), fetchedAt: Date())
        XCTAssertEqual(feed.departures(from: Station.byID["33S"]!), [])
    }
}

final class LineTests: XCTestCase {
    func testLineNamesFromFeedColors() {
        XCTAssertEqual(PathLine(feedColors: "D93A30", headsign: "Newark").name, "NWK–WTC")
        XCTAssertEqual(PathLine(feedColors: "65C100", headsign: "Hoboken").name, "HOB–WTC")
        XCTAssertEqual(PathLine(feedColors: "FF9900", headsign: "Journal Square").name, "JSQ–33")
        XCTAssertEqual(PathLine(feedColors: "4D92FB", headsign: "Hoboken").name, "HOB–33")
        let overnight = PathLine(feedColors: "4D92FB,FF9900", headsign: "Journal Square via Hoboken")
        XCTAssertEqual(overnight.name, "JSQ–33 via HOB")
        XCTAssertNotNil(overnight.accent)
        XCTAssertEqual(overnight.towards, "Journal Square")
    }

    /// Every line's card must meet WCAG AA, and keep its recognisable color.
    func testCardTextContrast() {
        for hex in ["D93A30", "65C100", "FF9900", "4D92FB"] {
            let raw = RGB(hex: hex)
            let (fill, ink) = raw.legibleCard()
            XCTAssertGreaterThanOrEqual(fill.contrast(with: ink), 4.5, hex)
            // Only darkened, by at most ~15%, never shifted in hue.
            XCTAssertGreaterThan(fill.r / max(raw.r, 0.001), 0.85, hex)
            XCTAssertEqual(fill.r / max(raw.r, 0.001), fill.g / max(raw.g, 0.001), accuracy: 0.01, hex)
        }
        // Light lines keep their exact color with dark text.
        XCTAssertEqual(RGB(hex: "FF9900").legibleCard().fill, RGB(hex: "FF9900"))
        XCTAssertEqual(RGB(hex: "FF9900").legibleCard().ink, .nearBlack)
        XCTAssertEqual(RGB(hex: "D93A30").legibleCard().ink, .white)
    }
}

final class PlanTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testListsNextTrainsRegardlessOfWalk() {
        // A train 2:30 away on a 5 min walk is still listed: the board shows timings.
        let plan = Plan.sample(at: now, walkMinutes: 5, minutes: [2, 8, 18])
        let snap = BoardSnapshot(plan: plan, at: now)
        XCTAssertEqual(snap.rows.map(\.minutes), [2, 8, 18])
        XCTAssertEqual(snap.walkMinutes, 5)
        XCTAssertEqual(snap.minutesList(2), "2 · 8")
    }

    func testDepartedTrainsDropOff() {
        let plan = Plan.sample(at: now, minutes: [3, 13])
        let after = plan.departures[0].date.addingTimeInterval(1)
        XCTAssertEqual(BoardSnapshot(plan: plan, at: after).rows.map(\.departure), [plan.departures[1]])
    }

    func testAtMostThreeRows() {
        let plan = Plan.sample(at: now, minutes: [3, 13, 23, 33, 43])
        XCTAssertEqual(BoardSnapshot(plan: plan, at: now).rows.count, 3)
    }

    func testWalkRoundsUp() {
        XCTAssertEqual(Plan.sample(at: now, walkMinutes: 2.1).walkMinutes, 3)
        XCTAssertEqual(Plan.sample(at: now, walkMinutes: 0.2).walkMinutes, 1)
    }

    func testViaHobokenRowUsesShortName() {
        let plan = Plan.sample(at: now, colors: "4D92FB,FF9900", headsign: "Journal Square via Hoboken")
        XCTAssertEqual(BoardSnapshot(plan: plan, at: now).rows.first?.label, "JSQ–33")
    }

    func testEmptyWhenNothingPosted() {
        XCTAssertTrue(BoardSnapshot(plan: .sample(at: now, minutes: []), at: now).rows.isEmpty)
        XCTAssertEqual(Station.byID["NWK"]?.note, "Change at Journal Sq")
    }

    func testPlanSurvivesSharedStorage() throws {
        let plan = Plan.sample(at: now)
        let decoded = try JSONDecoder().decode(Plan.self, from: JSONEncoder().encode(plan))
        XCTAssertEqual(decoded.departures, plan.departures)
        XCTAssertEqual(decoded.stationID, "33S")
    }
}

final class TimelineTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// Everything numeric on the board.
    private func shown(_ plan: Plan, _ t: Date) -> String {
        BoardSnapshot(plan: plan, at: t).rows.map { "\($0.departure.date.timeIntervalSince1970):\($0.minutes)" }
            .joined(separator: "|")
    }

    /// Between consecutive redraws the board must not change, apart from the
    /// deliberate `tickSlack` just before each redraw.
    private func assertNeverStale(_ plan: Plan, _ dates: [Date], file: StaticString = #filePath, line: UInt = #line) {
        let guardBand = TimelineBuilder.tickSlack + 0.01
        for (a, b) in zip(dates, dates.dropFirst()) where b.timeIntervalSince(a) > guardBand {
            XCTAssertEqual(shown(plan, a), shown(plan, b.addingTimeInterval(-guardBand)),
                           "board changed between redraws at \(a.timeIntervalSince(now))s and \(b.timeIntervalSince(now))s",
                           file: file, line: line)
        }
    }

    func testMinuteCountsNeverStale() {
        let plan = Plan.sample(at: now, walkMinutes: 4, minutes: [8, 18, 28, 38, 48])
        let dates = TimelineBuilder.redrawDates(for: plan, from: now)
        XCTAssertEqual(dates.first, now)
        XCTAssertEqual(dates, dates.sorted())
        XCTAssertEqual(Set(dates).count, dates.count)
        XCTAssertLessThanOrEqual(dates.last!, now.addingTimeInterval(TimelineBuilder.horizon + 1))
        assertNeverStale(plan, dates)
    }

    /// At Newport two terminals count down on different phases; neither may go stale.
    func testEveryShownNumberIsFreshAtNewport() {
        let now = self.now
        let deps = [(6.2, "33rd Street", "FF9900"), (9.7, "World Trade Center", "65C100"),
                    (16.2, "33rd Street", "FF9900"), (19.7, "World Trade Center", "65C100")]
            .map { Departure(date: now.addingTimeInterval($0.0 * 60), headsign: $0.1, lineColors: $0.2) }
        let plan = Plan(stationID: "NEW", walkSeconds: 150, departures: deps, computedAt: now,
                        originLatitude: 40.727, originLongitude: -74.034)
        let dates = TimelineBuilder.redrawDates(for: plan, from: now)
        assertNeverStale(plan, dates)
        XCTAssertLessThan(dates.count, 90, "timeline is bloated")
    }

    func testRedrawWhenATrainDeparts() {
        let plan = Plan.sample(at: now, minutes: [8, 18])
        let dates = TimelineBuilder.redrawDates(for: plan, from: now)
        XCTAssertTrue(dates.contains(plan.departures[0].date.addingTimeInterval(TimelineBuilder.tickSlack)))
    }

    func testReloadWindow() {
        let lots = Plan.sample(at: now, minutes: [30, 40, 50, 60])
        XCTAssertEqual(TimelineBuilder.reloadDate(for: lots, from: now), now.addingTimeInterval(TimelineBuilder.maxReloadInterval))
        // Two left: refetch as the first leaves (only one would remain).
        let two = Plan.sample(at: now, minutes: [8, 18])
        XCTAssertEqual(TimelineBuilder.reloadDate(for: two, from: now), two.departures[0].date)
        // Never sooner than the floor.
        let soon = Plan.sample(at: now, minutes: [1, 2])
        XCTAssertEqual(TimelineBuilder.reloadDate(for: soon, from: now), now.addingTimeInterval(TimelineBuilder.minReloadInterval))
        let none = Plan.sample(at: now, minutes: [])
        XCTAssertEqual(TimelineBuilder.reloadDate(for: none, from: now), now.addingTimeInterval(TimelineBuilder.minReloadInterval))
    }
}

final class HomeAndLinkTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func newport(_ deps: [(Double, String, String)]) -> Plan {
        Plan(stationID: "NEW", walkSeconds: 180,
             departures: deps.map { Departure(date: now.addingTimeInterval($0.0 * 60 + 30), headsign: $0.1, lineColors: $0.2) },
             computedAt: now, originLatitude: 40.727, originLongitude: -74.034)
    }

    func testNewportLeadsWithEachTerminalLikeRidePATH() {
        // Two WTC trains come before the first 33rd St one...
        let plan = newport([(3, "World Trade Center", "65C100"), (8, "World Trade Center", "65C100"),
                            (12, "33rd Street", "FF9900")])
        let rows = BoardSnapshot(plan: plan, at: now).rows
        // ...but both terminals lead, so cutting to two rows keeps both.
        XCTAssertEqual(rows.map(\.label), ["WTC", "33rd St", "WTC"])
        XCTAssertEqual(rows.map(\.minutes), [3, 12, 8])
    }

    func testNewportWithOneTerminalPosted() {
        let rows = BoardSnapshot(plan: newport([(5, "World Trade Center", "65C100")]), at: now).rows
        XCTAssertEqual(rows.map(\.label), ["WTC"])
    }

    func testAwayFromHomeRowsAreByTime() {
        let snap = BoardSnapshot(plan: .sample(at: now), at: now)
        XCTAssertEqual(snap.rows.map(\.minutes), [8, 18, 28])
        XCTAssertEqual(snap.rows.first?.label, "JSQ–33")
    }

    func testGoogleMapsLink() {
        let url = Station.byID["33S"]!.googleMapsWalkingURL.absoluteString
        XCTAssertEqual(url, "https://www.google.com/maps/dir/?api=1&destination=33rd%20Street%20PATH%20Station,%20New%20York,%20NY&travelmode=walking")
        XCTAssertEqual(Station.byID["NEW"]!.mapsQuery, "Newport PATH Station, Jersey City, NJ")
        let entry = BoardEntry(date: now, state: .plan(.sample(at: now, stationID: "WTC")))
        XCTAssertEqual(entry.deepLink.absoluteString, "pathhome://walk?station=WTC")
    }

    func testOnlyRoutesTheRunnerUpWhenItCouldWin() {
        XCTAssertEqual(Planner.candidates(near: Station.byID["NEW"]!.location).map(\.id), ["NEW"])
        let between = CLLocation(latitude: 40.7216, longitude: -74.0334)
        XCTAssertEqual(Set(Planner.candidates(near: between).map(\.id)), ["NEW", "EXP"])
    }

    func testFreshPlanFromSameSpotIsReusedWithoutNetwork() async throws {
        let previous = Plan.sample(at: now)
        let nearby = CLLocation(latitude: previous.originLatitude + 0.0003, longitude: previous.originLongitude)
        let plan = try await Planner.plan(from: nearby, previous: previous, now: now.addingTimeInterval(30))
        XCTAssertEqual(plan.computedAt, previous.computedAt)
    }
}

final class RefreshAndRankingTests: XCTestCase {
    /// A refresh tap must refetch even when a fresh plan from the same spot exists,
    /// but keep the walk it already measured. Hits the live feed.
    func testRefreshTapRefetchesButKeepsTheWalk() async throws {
        let previous = Plan.sample(at: Date().addingTimeInterval(-5), stationID: "33S", walkMinutes: 4)
        let plan = try await Planner.plan(from: previous.origin, previous: previous, forceFresh: true)
        XCTAssertGreaterThan(plan.computedAt, previous.computedAt)
        XCTAssertEqual(plan.walkSeconds, previous.walkSeconds)
        XCTAssertEqual(plan.stationID, "33S")
    }

    func testSmartStackRanksUrgentTrainsHigher() {
        let now = Date()
        func score(_ minutes: Double) -> Float {
            BoardEntry(date: now, state: .plan(.sample(at: now, walkMinutes: 4, minutes: [minutes]))).relevance!.score
        }
        XCTAssertGreaterThan(score(6), score(12))
        XCTAssertGreaterThan(score(12), score(40))
        XCTAssertEqual(BoardEntry(date: now, state: .needsLocation).relevance?.score, 0)
    }
}

/// Hits the real PANYNJ feed. Catches the feed renaming headsigns or station codes.
final class LiveFeedTests: XCTestCase {
    func testEveryStationIsInTheFeedAndHeadsignsAreKnown() async throws {
        let (data, _) = try await URLSession.shared.data(from: URL(string: "https://www.panynj.gov/bin/portauthority/ridepath.json")!)
        let feed = try PathFeed(data: data, fetchedAt: Date())
        let codes = Set(feed.body.results.map(\.consideredStation))
        XCTAssertEqual(codes, Set(Station.all.map(\.id)), "Station codes changed")

        let known = ["world trade", "33rd", "hoboken", "journal", "newark"]
        for result in feed.body.results {
            for m in result.destinations.flatMap(\.messages) {
                XCTAssertTrue(known.contains { m.headSign.lowercased().contains($0) }, "Unknown headsign \(m.headSign)")
                XCTAssertNotEqual(PathLine(feedColors: m.lineColor, headsign: m.headSign).name, "PATH", "Unknown color \(m.lineColor)")
            }
        }
    }
}
