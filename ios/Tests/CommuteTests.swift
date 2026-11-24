import CoreLocation
import XCTest
@testable import PathHome

final class CommuteTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testFreshnessHasExplicitBoundaries() {
        XCTAssertEqual(PlanFreshness(asOf: now, now: now.addingTimeInterval(119)), .fresh)
        XCTAssertEqual(PlanFreshness(asOf: now, now: now.addingTimeInterval(120)), .aging)
        XCTAssertEqual(PlanFreshness(asOf: now, now: now.addingTimeInterval(300)), .expired)
        XCTAssertEqual(PlanFreshness(asOf: now.addingTimeInterval(60), now: now), .expired)
    }

    func testRecommendationIncludesWalkAndBufferWithoutRoundingTrainEarlier() throws {
        let plan = Plan.sample(at: now, walkMinutes: 4, minutes: [5, 8, 18])
        let r = try XCTUnwrap(CommuteRecommendation.make(plan: plan, now: now, bufferMinutes: 2))
        XCTAssertEqual(r.departure, plan.departures[1])
        XCTAssertEqual(r.leaveAt, plan.departures[1].date.addingTimeInterval(-360))
        XCTAssertEqual(r.leaveInMinutes(at: now), 2)
        XCTAssertTrue(r.skippedTightTrain)
    }

    func testExactCatchabilityBoundaryIsIncluded() throws {
        let plan = Plan.sample(at: now, walkMinutes: 4, minutes: [5.5])
        let r = try XCTUnwrap(CommuteRecommendation.make(plan: plan, now: now, bufferMinutes: 2))
        XCTAssertEqual(r.leaveAt, now)
        XCTAssertEqual(r.leaveInMinutes(at: now), 0)
        XCTAssertNil(CommuteRecommendation.make(plan: plan, now: now.addingTimeInterval(1), bufferMinutes: 2))
    }

    func testBufferIsClampedAndDirectionsAreRespected() throws {
        let home = Station.byID["NEW"]!
        let deps = [Departure(date: now.addingTimeInterval(500), headsign: "33rd Street", lineColors: "FF9900"),
                    Departure(date: now.addingTimeInterval(600), headsign: "World Trade Center", lineColors: "65C100")]
        let plan = Plan(stationID: "NEW", walkSeconds: 120, departures: deps, computedAt: now,
                        originLatitude: home.latitude, originLongitude: home.longitude)
        let r = try XCTUnwrap(CommuteRecommendation.make(plan: plan, now: now, bufferMinutes: 99,
                            destinations: Destination.newport.filter { $0.id == "WTC" }))
        XCTAssertEqual(r.departure.headsign, "World Trade Center")
        XCTAssertEqual(r.leaveAt, deps[1].date.addingTimeInterval(-300))
    }

    func testExpiredOfflineOrUnknownWalkNeverProducesLeaveAdvice() {
        var plan = Plan.sample(at: now, minutes: [20])
        XCTAssertNil(CommuteRecommendation.make(plan: plan, now: now.addingTimeInterval(300), bufferMinutes: 2))
        XCTAssertNil(CommuteRecommendation.make(plan: plan, now: now, bufferMinutes: 2, offline: true))
        plan.walkIsKnown = false
        XCTAssertNil(CommuteRecommendation.make(plan: plan, now: now, bufferMinutes: 2))
    }

    func testOldLocationSuppressesWalkAdviceEvenWithFreshTrains() {
        var plan = Plan.sample(at: now, minutes: [20])
        plan.locationDate = now.addingTimeInterval(-301)
        XCTAssertNil(CommuteRecommendation.make(plan: plan, now: now, bufferMinutes: 2))
    }

    func testScheduledRecommendationIsExplicitlyAnEstimate() throws {
        var plan = Plan.sample(at: now, minutes: [20])
        plan = Plan(stationID: plan.stationID, walkSeconds: plan.walkSeconds,
                    departures: plan.departures.map { Departure(date: $0.date, headsign: $0.headsign, lineColors: $0.lineColors, scheduled: true) },
                    computedAt: now, originLatitude: plan.originLatitude, originLongitude: plan.originLongitude)
        XCTAssertTrue(try XCTUnwrap(CommuteRecommendation.make(plan: plan, now: now, bufferMinutes: 2)).departure.scheduled)
    }

    func testFixedStationWorksWithoutLocationAndNeverBorrowsAnotherStationsPlan() async throws {
        let data = Data(#"{"results":[{"consideredStation":"WTC","destinations":[{"messages":[{"headSign":"Hoboken","lineColor":"65C100","secondsToArrival":"600"}]}]}]}"#.utf8)
        let deps = Planner.Dependencies(fetch: { try PathFeed(data: data, fetchedAt: self.now) },
                                        walk: { _, _ in XCTFail("No location must not trigger routing"); return 0 })
        let plan = try await Planner.plan(from: nil, stationID: "WTC", previous: .sample(at: now), now: now, dependencies: deps)
        XCTAssertEqual(plan.stationID, "WTC")
        XCTAssertFalse(plan.walkIsKnown)
        XCTAssertFalse(plan.departures.isEmpty)
    }

    func testAutomaticModeNeverReusesAnOverride() async throws {
        let here = Station.byID["NEW"]!.location
        let data = Data(#"{"results":[]}"#.utf8)
        let deps = Planner.Dependencies(fetch: { try PathFeed(data: data, fetchedAt: self.now) }, walk: { _, _ in 30 })
        let previous = Plan(stationID: "EXP", walkSeconds: 400, departures: [], computedAt: now,
                            originLatitude: here.coordinate.latitude, originLongitude: here.coordinate.longitude,
                            selectionID: "EXP")
        let plan = try await Planner.plan(from: here, previous: previous, now: now, dependencies: deps)
        XCTAssertEqual(plan.stationID, "NEW")
        XCTAssertNil(plan.selectionID)
    }

    func testCacheSeparatesAutomaticAndFixedStations() {
        let auto = Plan.sample(at: now, stationID: "33S")
        let fixed = Plan.sample(at: now, stationID: "WTC")
        defer { SharedStore.save(nil, for: "test-WTC"); SharedStore.save(nil, for: "test-auto") }
        SharedStore.save(auto, for: "test-auto")
        SharedStore.save(fixed, for: "test-WTC")
        XCTAssertEqual(SharedStore.plan(for: "test-auto")?.stationID, "33S")
        XCTAssertEqual(SharedStore.plan(for: "test-WTC")?.stationID, "WTC")
    }
}
