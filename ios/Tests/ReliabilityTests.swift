import CoreLocation
import XCTest
@testable import PathHome

final class ReliabilityTests: XCTestCase {
    func testNewportHobokenUsesOnlyCurrentPostedTrainsIncludingForLegacyPlans() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let station = Station.byID["NEW"]!
        let destination = Destination.newport.filter { $0.id == "HOB" }
        let posted = Departure(date: now.addingTimeInterval(600), headsign: "Hoboken", lineColors: "65C100")
        let projected = Planner.withTimetable([posted], at: station, now: now)
        XCTAssertEqual(projected.filter { destination[0].includes($0) }, [posted])
        XCTAssertFalse(Planner.withTimetable([], at: station, now: now).contains(where: destination[0].includes))

        var oldEstimate = posted
        oldEstimate.scheduled = true
        let plan = Plan(stationID: station.id, walkSeconds: 420, departures: [posted, oldEstimate],
                        computedAt: now, originLatitude: station.latitude, originLongitude: station.longitude)
        XCTAssertEqual(BoardSnapshot(plan: plan, at: now, showing: destination).rows.first?.trains.count, 1)
        XCTAssertTrue(BoardSnapshot(plan: plan, at: now.addingTimeInterval(301), showing: destination).rows.isEmpty)
    }

    func testNewportSavedWalkSurvivesRefreshWithoutBecomingCurrentAdvice() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let measured = now.addingTimeInterval(-60)
        var cached = Plan.sample(at: measured, stationID: "NEW", walkMinutes: 7)
        cached.locationDate = measured
        let feed = try PathFeed(data: Data(#"{"results":[]}"#.utf8), fetchedAt: now)
        let dependencies = Planner.Dependencies(fetch: { feed }, walk: { _, _ in
            XCTFail("Missing location must not request a new walking route")
            return 0
        })
        let plan = try await Planner.plan(from: nil, previous: cached, now: now, forceFresh: true,
                                          allowSavedLocation: true, dependencies: dependencies)
        XCTAssertEqual(plan.stationID, "NEW")
        XCTAssertNil(plan.selectionID)
        XCTAssertEqual(plan.locationDate, measured)
        XCTAssertEqual(BoardSnapshot(plan: plan, at: now).walkLabel, "~7 min")
        XCTAssertFalse(plan.hasReliableWalk(at: now))
        XCTAssertFalse(BoardSnapshot(plan: plan, at: measured.addingTimeInterval(3600)).hasWalk)
    }

    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testNonFiniteFeedCountsAreDiscarded() throws {
        let data = Data(#"{"results":[{"consideredStation":"NEW","destinations":[{"messages":[{"headSign":"33rd Street","lineColor":"FF9900","secondsToArrival":"nan"},{"headSign":"33rd Street","lineColor":"FF9900","secondsToArrival":"inf"},{"headSign":"33rd Street","lineColor":"FF9900","secondsToArrival":"90"}]}]}]}"#.utf8)
        let departures = try PathFeed(data: data, fetchedAt: now).departures(from: Station.byID["NEW"]!)
        XCTAssertEqual(departures.count, 1)
        XCTAssertTrue(departures.allSatisfy { $0.date.timeIntervalSince1970.isFinite })
    }

    func testStaleFeedTimestampIsNotMadeFreshByFetchingAgain() throws {
        let data = Data(#"{"results":[{"consideredStation":"NEW","destinations":[{"messages":[{"headSign":"33rd Street","lineColor":"FF9900","secondsToArrival":"900","lastUpdated":"2020-01-01T00:00:00Z"}]}]}]}"#.utf8)
        let feed = try PathFeed(data: data, fetchedAt: now)
        XCTAssertEqual(PlanFreshness(asOf: feed.predictionDate(from: Station.byID["NEW"]!), now: now), .expired)
    }

    func testFixedStationReusesWalkButForcedRefreshFetchesNewTrains() async throws {
        let location = CLLocation(coordinate: Station.byID["WTC"]!.coordinate, altitude: 0,
                                 horizontalAccuracy: 10, verticalAccuracy: -1, timestamp: now)
        let data = Data(#"{"results":[]}"#.utf8)
        let previous = Plan(stationID: "WTC", walkSeconds: 123, departures: [], computedAt: now,
                            originLatitude: location.coordinate.latitude, originLongitude: location.coordinate.longitude,
                            locationDate: now, selectionID: "WTC")
        var fetched = false
        let dependencies = Planner.Dependencies(fetch: { fetched = true; return try PathFeed(data: data, fetchedAt: self.now.addingTimeInterval(1)) },
            walk: { _, _ in XCTFail("Same origin must reuse the measured walk"); return 0 })
        let result = try await Planner.plan(from: location, stationID: "WTC", previous: previous,
                                           now: now, forceFresh: true, dependencies: dependencies)
        XCTAssertTrue(fetched)
        XCTAssertEqual(result.walkSeconds, 123)
        XCTAssertEqual(result.selectionID, "WTC")
    }

    func testPoorLocationStillAllowsFixedDeparturesButNoWalkingAdvice() async throws {
        let location = CLLocation(coordinate: Station.byID["WTC"]!.coordinate, altitude: 0,
                                 horizontalAccuracy: 2000, verticalAccuracy: -1, timestamp: now)
        let data = Data(#"{"results":[]}"#.utf8)
        let dependencies = Planner.Dependencies(fetch: { try PathFeed(data: data, fetchedAt: self.now) },
            walk: { _, _ in XCTFail("Inaccurate location cannot produce walking guidance"); return 0 })
        let plan = try await Planner.plan(from: location, stationID: "WTC", previous: nil, now: now, dependencies: dependencies)
        XCTAssertFalse(plan.hasReliableWalk(at: now))
    }

    func testOfflineBoardNeverClaimsLiveEvenWithRecentData() {
        let plan = Plan.sample(at: now)
        XCTAssertFalse(BoardSnapshot(plan: plan, at: now, offline: true).rows[0].next.isLive)
    }

    func testWidgetIntentDefaultsAndPerInstanceChoices() {
        let defaultConfig = BoardConfigurationIntent()
        XCTAssertNil(defaultConfig.options.stationID)
        let fixed = BoardConfigurationIntent()
        fixed.station = .WTC
        fixed.directions = .wtc
        fixed.display = .recommendation
        XCTAssertEqual(fixed.options.stationID, "WTC")
        XCTAssertEqual(fixed.options.destinations.map(\.id), ["WTC"])
        XCTAssertTrue(fixed.options.recommends)
        XCTAssertNil(defaultConfig.options.stationID)
    }
}
