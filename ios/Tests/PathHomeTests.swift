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

    func testCatchableRespectsWalk() {
        let plan = Plan.sample(at: now, walkMinutes: 5, minutes: [3, 8, 18])
        // +3:30 is unreachable on a 5 min walk; +8:30 and +18:30 are fine.
        XCTAssertEqual(plan.catchable(at: now).count, 2)
        XCTAssertEqual(plan.leaveBy(plan.catchable(at: now)[0]), now.addingTimeInterval(8 * 60 + 30 - 300))
    }

    func testSnapshotNumbers() {
        let plan = Plan.sample(at: now, walkMinutes: 4, minutes: [8, 18, 28])
        let snap = BoardSnapshot(plan: plan, at: now).primary!
        XCTAssertEqual(snap.minutesToNext, 8)
        XCTAssertEqual(snap.minutesToLeave, 4)
        XCTAssertEqual(snap.leaveText, "Leave in 4 min")
        XCTAssertEqual(snap.followingText, "then 18, 28")
        // Right before you must leave it says leave now, then the card moves on.
        let late = BoardSnapshot(plan: plan, at: plan.leaveBy(plan.departures[0]).addingTimeInterval(-20)).primary!
        XCTAssertEqual(late.leaveText, "Leave now")
        XCTAssertEqual(late.next, plan.departures[0])
        let missed = BoardSnapshot(plan: plan, at: plan.leaveBy(plan.departures[0]).addingTimeInterval(1)).primary!
        XCTAssertEqual(missed.next, plan.departures[1])
    }

    func testHomeAndEmptyStates() {
        let home = Plan.sample(at: now, stationID: "NEW", minutes: [])
        XCTAssertTrue(BoardSnapshot(plan: home, at: now).station.isHome)
        let none = Plan.sample(at: now, minutes: [])
        XCTAssertNil(BoardSnapshot(plan: none, at: now).primary)
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

    /// Everything on the board, as numbers and which train each card shows.
    private func shown(_ plan: Plan, _ t: Date) -> String {
        BoardSnapshot(plan: plan, at: t).groups
            .map { g in "\(g.next?.date.timeIntervalSince1970 ?? 0):\(g.minutesToNext),\(g.minutesToLeave),\(g.following)" }
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

    func testMinuteCountTicksDownOneAtATime() {
        let plan = Plan.sample(at: now, walkMinutes: 4, minutes: [8, 18, 28, 38, 48])
        let dates = TimelineBuilder.redrawDates(for: plan, from: now)
        XCTAssertEqual(dates.first, now)
        XCTAssertEqual(dates, dates.sorted())
        XCTAssertEqual(Set(dates).count, dates.count)
        XCTAssertLessThanOrEqual(dates.last!, now.addingTimeInterval(TimelineBuilder.horizon))
        assertNeverStale(plan, dates)
        XCTAssertLessThanOrEqual(zip(dates, dates.dropFirst()).map { $1.timeIntervalSince($0) }.max()!, 60.001)
    }

    /// At Newport two terminals count down on different phases; neither may go stale.
    func testEveryShownNumberIsFreshAtNewport() {
        let now = self.now
        let deps = [(6.2, "33rd Street", "FF9900"), (9.7, "World Trade Center", "65C100"),
                    (16.2, "33rd Street", "FF9900"), (19.7, "World Trade Center", "65C100"),
                    (26.2, "33rd Street", "FF9900")]
            .map { Departure(date: now.addingTimeInterval($0.0 * 60), headsign: $0.1, lineColors: $0.2) }
        let plan = Plan(stationID: "NEW", walkSeconds: 150, departures: deps, computedAt: now,
                        originLatitude: 40.727, originLongitude: -74.034)
        let dates = TimelineBuilder.redrawDates(for: plan, from: now)
        assertNeverStale(plan, dates)
        XCTAssertLessThan(dates.count, 120, "timeline is bloated")
    }

    func testRedrawAtTheMomentATrainBecomesUncatchable() {
        let plan = Plan.sample(at: now, walkMinutes: 4, minutes: [8, 18])
        let dates = TimelineBuilder.redrawDates(for: plan, from: now)
        XCTAssertTrue(dates.contains(plan.leaveBy(plan.departures[0]).addingTimeInterval(1)))
    }

    func testReloadWindow() {
        let lots = Plan.sample(at: now, walkMinutes: 4, minutes: [30, 40, 50, 60])
        let r1 = TimelineBuilder.reloadDate(for: lots, from: now)
        XCTAssertEqual(r1, now.addingTimeInterval(TimelineBuilder.maxReloadInterval))

        // Two trains left: refetch when the first one stops being catchable.
        let two = Plan.sample(at: now, walkMinutes: 4, minutes: [12, 22])
        XCTAssertEqual(TimelineBuilder.reloadDate(for: two, from: now), two.leaveBy(two.departures[0]))

        // Never sooner than the floor, even with nothing catchable.
        let none = Plan.sample(at: now, walkMinutes: 4, minutes: [2])
        XCTAssertEqual(TimelineBuilder.reloadDate(for: none, from: now), now.addingTimeInterval(TimelineBuilder.minReloadInterval))
    }
}

final class HomeAndLinkTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testNewportShowsBothTerminalsLikeRidePATH() {
        let wtc = Departure(date: now.addingTimeInterval(9 * 60 + 30), headsign: "World Trade Center", lineColors: "65C100")
        let w2 = Departure(date: now.addingTimeInterval(19 * 60 + 30), headsign: "World Trade Center", lineColors: "65C100")
        let s33 = Departure(date: now.addingTimeInterval(6 * 60 + 30), headsign: "33rd Street", lineColors: "FF9900")
        let plan = Plan(stationID: "NEW", walkSeconds: 180, departures: [s33, wtc, w2], computedAt: now,
                        originLatitude: 40.727, originLongitude: -74.034)
        let snap = BoardSnapshot(plan: plan, at: now)
        XCTAssertEqual(snap.groups.map(\.destination.short), ["WTC", "33rd St"])
        XCTAssertEqual(snap.groups[0].minutesToNext, 9)
        XCTAssertEqual(snap.groups[0].followingText, "then 19")
        XCTAssertEqual(snap.groups[1].minutesToNext, 6)
        // One-number layouts pick whichever terminal's train is sooner.
        XCTAssertEqual(snap.primary?.destination.short, "33rd St")
        // A terminal with nothing catchable still gets its slot, empty.
        let later = BoardSnapshot(plan: plan, at: now.addingTimeInterval(5 * 60))
        XCTAssertNil(later.groups[1].next)
        XCTAssertEqual(later.groups.count, 2)
    }

    func testAwayFromHomeIsOneGroup() {
        XCTAssertEqual(BoardSnapshot(plan: .sample(at: now), at: now).groups.count, 1)
    }

    func testGoogleMapsLink() {
        let url = Station.byID["33S"]!.googleMapsWalkingURL.absoluteString
        XCTAssertEqual(url, "https://www.google.com/maps/dir/?api=1&destination=40.7488,-73.9884&travelmode=walking")
        let entry = BoardEntry(date: now, state: .plan(.sample(at: now, stationID: "WTC")))
        XCTAssertEqual(entry.deepLink.absoluteString, "pathhome://walk?station=WTC")
    }

    func testOnlyRoutesTheRunnerUpWhenItCouldWin() {
        // Standing right at Newport: the next station is far behind, route one.
        XCTAssertEqual(Planner.candidates(near: Station.byID["NEW"]!.location).map(\.id), ["NEW"])
        // Halfway between Newport and Exchange Place: both are plausible.
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

final class JustMissedTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// The real case seen live: one JSQ train 75s out on a 2 min walk.
    func testTooCloseToWalkIsReportedNotHidden() {
        let plan = Plan.sample(at: now, walkMinutes: 2, minutes: [0.75])  // departs +1:15
        let snap = BoardSnapshot(plan: plan, at: now)
        XCTAssertNil(snap.primary)
        XCTAssertEqual(snap.justMissed, plan.departures[0])
        XCTAssertEqual(snap.minutesToMissed, 1)
        // Once it actually departs there's nothing to name.
        XCTAssertNil(BoardSnapshot(plan: plan, at: plan.departures[0].date.addingTimeInterval(1)).justMissed)
        // And the board redraws at that moment to drop it.
        XCTAssertTrue(TimelineBuilder.redrawDates(for: plan, from: now).contains(plan.departures[0].date.addingTimeInterval(1)))
    }

    func testCatchableTrainIsNotReportedAsMissed() {
        let plan = Plan.sample(at: now, walkMinutes: 2, minutes: [10])
        XCTAssertNil(BoardSnapshot(plan: plan, at: now).justMissed)
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
