import CoreLocation
import XCTest
@testable import PathHome

final class EnergyTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @MainActor
    func testScheduledWidgetDoesNotRequestLocationButManualRefreshCan() async {
        let fix = CLLocation(latitude: 40.73, longitude: -74.03)
        var requests = 0
        func request() async -> CLLocation? { requests += 1; return fix }
        let scheduled = await WidgetPlanRefresh.resolveFix(cached: nil, requestIfNeeded: false,
                                                           at: fix.timestamp, request: request)
        XCTAssertNil(scheduled)
        XCTAssertEqual(requests, 0)
        let stale = await WidgetPlanRefresh.resolveFix(cached: fix, requestIfNeeded: false,
            at: fix.timestamp.addingTimeInterval(301), request: request)
        XCTAssertNil(stale)
        XCTAssertEqual(requests, 0)
        let manual = await WidgetPlanRefresh.resolveFix(cached: nil, requestIfNeeded: true,
                                                        at: fix.timestamp, request: request)
        XCTAssertEqual(manual, fix)
        XCTAssertEqual(requests, 1)
        let cached = await WidgetPlanRefresh.resolveFix(cached: fix, requestIfNeeded: true,
                                                        at: fix.timestamp, request: request)
        XCTAssertEqual(cached, fix)
        XCTAssertEqual(requests, 1)
    }

    func testWidgetWaitsLongerToFetchWhenNoLiveTrainsArePosted() {
        let empty = Plan.sample(at: now, minutes: [])
        let busy = Plan.sample(at: now, minutes: [1, 5])
        XCTAssertEqual(TimelineBuilder.reloadDate(for: empty, from: now), now.addingTimeInterval(900))
        XCTAssertEqual(TimelineBuilder.reloadDate(for: busy, from: now), now.addingTimeInterval(600))
    }

    @MainActor
    func testNewerLocationAcrossTheRiverInvalidatesSavedNewportWalk() {
        let saved = Plan.sample(at: now.addingTimeInterval(-2400), stationID: "NEW")
        let moved = CLLocation(coordinate: Station.byID["33S"]!.coordinate, altitude: 0,
                               horizontalAccuracy: 50, verticalAccuracy: -1,
                               timestamp: now.addingTimeInterval(-600))
        XCTAssertTrue(WidgetPlanRefresh.canUseSavedLocation(previous: saved, latestFix: nil, at: now))
        XCTAssertFalse(WidgetPlanRefresh.canUseSavedLocation(previous: saved, latestFix: moved, at: now))
    }

    func testTwoWidgetsCanReuseFreshDeparturesWithASavedWalk() async throws {
        let saved = Plan.sample(at: now.addingTimeInterval(-600), stationID: "NEW")
        let feed = try PathFeed(data: Data(#"{"results":[]}"#.utf8), fetchedAt: now)
        var fetches = 0
        let dependencies = Planner.Dependencies(fetch: {
            fetches += 1
            return feed
        }, walk: { _, _ in
            XCTFail("A saved walk must not trigger a routing request")
            return 0
        })
        let first = try await Planner.plan(from: nil, previous: saved, now: now,
                                           allowSavedLocation: true, dependencies: dependencies)
        let second = try await Planner.plan(from: nil, previous: first, now: now.addingTimeInterval(30),
                                            allowSavedLocation: true, dependencies: dependencies)
        XCTAssertTrue(second.walkIsSaved)
        XCTAssertEqual(second.walkMeasuredAt, saved.walkMeasuredAt)
        XCTAssertEqual(fetches, 1)
    }

    func testDisplayScheduleUsesBoundariesInsteadOfSecondTicks() {
        let plan = Plan.sample(at: now, stationID: "33S", walkMinutes: 6, minutes: [4, 14, 24])
        let dates = AppUpdateSchedule.dates(for: plan, from: now, bufferMinutes: 2)
        XCTAssertEqual(dates.first, now)
        XCTAssertEqual(dates, dates.sorted())
        XCTAssertEqual(Set(dates).count, dates.count)
        XCTAssertLessThan(dates.count, 200, "One-hour display schedule should avoid the old 3,600 second ticks")
        XCTAssertTrue(dates.contains(plan.asOf.addingTimeInterval(60.5)))
        XCTAssertTrue(dates.contains(plan.asOf.addingTimeInterval(120)))
        XCTAssertTrue(dates.contains(plan.asOf.addingTimeInterval(300)))
    }

    func testDisplayChangesDoNotOccurBetweenScheduledUpdates() {
        let plan = Plan.sample(at: now, stationID: "33S", walkMinutes: 6, minutes: [4, 14, 24])
        func display(_ date: Date) -> String {
            let counts = BoardSnapshot(plan: plan, at: date).rows.flatMap(\.trains).map { String($0.minutes) }
            let advice = CommuteRecommendation.make(plan: plan, now: date, bufferMinutes: 2)?.leaveInMinutes(at: date)
            return counts.joined(separator: ",") + ":\(String(describing: advice)):\(plan.freshnessText(at: date))"
        }
        let dates = AppUpdateSchedule.dates(for: plan, from: now, bufferMinutes: 2)
        for (a, b) in zip(dates, dates.dropFirst()) where b.timeIntervalSince(a) > 0.6 {
            XCTAssertEqual(display(a), display(b.addingTimeInterval(-0.51)), "Visible values changed between refresh boundaries")
        }
    }

    func testPollingSlowsForLowPowerModeAndFailures() {
        XCTAssertEqual(ForegroundRefreshPolicy.delay(lowPower: false, failures: 0), .seconds(30))
        XCTAssertEqual(ForegroundRefreshPolicy.delay(lowPower: true, failures: 0), .seconds(60))
        XCTAssertEqual(ForegroundRefreshPolicy.delay(lowPower: false, failures: 1), .seconds(60))
        XCTAssertEqual(ForegroundRefreshPolicy.delay(lowPower: false, failures: 2), .seconds(120))
        XCTAssertEqual(ForegroundRefreshPolicy.delay(lowPower: true, failures: 99), .seconds(120))
    }

    func testRoutineWidgetRequestsCoalesceButManualRefreshIsImmediate() {
        var gate = WidgetReloadGate()
        XCTAssertTrue(gate.shouldReload(at: now, immediate: false))
        XCTAssertFalse(gate.shouldReload(at: now.addingTimeInterval(30), immediate: false))
        XCTAssertFalse(gate.shouldReload(at: now.addingTimeInterval(299), immediate: false))
        XCTAssertTrue(gate.shouldReload(at: now.addingTimeInterval(300), immediate: false))
        XCTAssertTrue(gate.shouldReload(at: now.addingTimeInterval(301), immediate: true))
        XCTAssertFalse(gate.shouldReload(at: now.addingTimeInterval(302), immediate: false))
    }

    func testFreshnessLabelNeedsNoSecondTimer() {
        let plan = Plan.sample(at: now)
        XCTAssertEqual(plan.freshnessText(at: now), plan.freshnessText(at: now.addingTimeInterval(59)))
        XCTAssertNotEqual(plan.freshnessText(at: now), plan.freshnessText(at: now.addingTimeInterval(60)))
    }

    func testDisplayScheduleContinuesDuringLongOutages() {
        let schedule = DepartureTimelineSchedule(plan: .sample(at: now),
            bufferMinutes: 2, destinations: Destination.newport)
        let entries = Array(schedule.entries(from: now, mode: .normal).prefix(400))
        XCTAssertGreaterThan(entries.last!.timeIntervalSince(now), 3 * 3600)
        XCTAssertEqual(entries, entries.sorted())
        XCTAssertEqual(Set(entries).count, entries.count)
    }

    func testLocationCallbacksShareBackoffAndCachedPlansDoNotEraseFailures() {
        var gate = AutomaticRefreshGate()
        XCTAssertTrue(gate.begin(at: now, lowPower: false, userInitiated: false))
        gate.failed()
        for seconds in [1.0, 15, 30, 59] {
            XCTAssertFalse(gate.begin(at: now.addingTimeInterval(seconds), lowPower: false, userInitiated: false))
        }
        XCTAssertTrue(gate.begin(at: now.addingTimeInterval(60), lowPower: false, userInitiated: false))
        gate.succeeded(fetchedNewPlan: false)
        XCTAssertEqual(gate.failures, 1)
        gate.failed()
        XCTAssertFalse(gate.begin(at: now.addingTimeInterval(179), lowPower: false, userInitiated: false))
        XCTAssertTrue(gate.begin(at: now.addingTimeInterval(180), lowPower: false, userInitiated: false))
        gate.succeeded(fetchedNewPlan: true)
        XCTAssertEqual(gate.delay(lowPower: false), .seconds(30))
    }

    func testManualRefreshBypassesAutomaticGateAndLowPowerLimitsLocationRequests() {
        var gate = AutomaticRefreshGate()
        XCTAssertTrue(gate.begin(at: now, lowPower: true, userInitiated: false))
        XCTAssertFalse(gate.begin(at: now.addingTimeInterval(30), lowPower: true, userInitiated: false))
        gate.failed()
        XCTAssertTrue(gate.begin(at: now.addingTimeInterval(31), lowPower: true, userInitiated: true))
        XCTAssertEqual(gate.failures, 0)
        XCTAssertFalse(gate.begin(at: now.addingTimeInterval(32), lowPower: true, userInitiated: false))
    }
}
