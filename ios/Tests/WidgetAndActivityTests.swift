import XCTest
@testable import PathHome

final class WidgetAndActivityTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testWidgetOptionsDoNotChangeAppSettings() {
        let before = SharedStore.newportDestinationIDs
        let options = WidgetOptions(stationID: "WTC", destinationIDs: ["WTC"], recommends: true)
        XCTAssertEqual(options.cacheKey, "WTC")
        XCTAssertEqual(options.destinations.map(\.id), ["WTC"])
        XCTAssertEqual(SharedStore.newportDestinationIDs, before)
        XCTAssertEqual(WidgetOptions().cacheKey, "automatic")
    }

    func testTimelineIncludesFreshnessAndAdviceBoundaries() throws {
        let plan = Plan.sample(at: now, walkMinutes: 4, minutes: [8, 18])
        let dates = TimelineBuilder.redrawDates(for: plan, from: now)
        XCTAssertTrue(dates.contains(now.addingTimeInterval(120)))
        XCTAssertTrue(dates.contains(now.addingTimeInterval(300)))
        let leave = plan.departures[0].date.addingTimeInterval(-360)
        XCTAssertTrue(dates.contains { abs($0.timeIntervalSince(leave)) < 1 })
    }

    func testExpiredPredictionsAreNotMarkedLiveOnBoard() {
        let plan = Plan.sample(at: now, minutes: [20])
        let fresh = BoardSnapshot(plan: plan, at: now)
        let old = BoardSnapshot(plan: plan, at: now.addingTimeInterval(300))
        XCTAssertTrue(fresh.rows[0].next.isLive)
        XCTAssertFalse(old.rows[0].next.isLive)
    }

    func testActivityHasPredictionDeadlineAndStableTrainIdentity() throws {
        let plan = Plan.sample(at: now, minutes: [8, 18])
        let r = try XCTUnwrap(CommuteRecommendation.make(plan: plan, now: now, bufferMinutes: 2))
        let state = CommuteActivity.ContentState(recommendation: r, plan: plan)
        XCTAssertEqual(state.departureAt, r.departure.date)
        XCTAssertEqual(state.leaveAt, r.leaveAt)
        XCTAssertEqual(state.predictionAt, plan.asOf)
        XCTAssertEqual(state.staleAt, plan.asOf.addingTimeInterval(120))
        XCTAssertEqual(state.status(at: now), .ready)
        XCTAssertEqual(state.status(at: now.addingTimeInterval(120)), .checkApp)
        XCTAssertEqual(state.status(at: state.departureAt), .departed)
    }

    func testActivityDoesNotSwitchToTheNextTrainOnRefresh() throws {
        let plan = Plan.sample(at: now, minutes: [8, 18])
        let r = try XCTUnwrap(CommuteRecommendation.make(plan: plan, now: now, bufferMinutes: 2))
        let state = CommuteActivity.ContentState(recommendation: r, plan: plan)
        let afterFirstLeft = now.addingTimeInterval(10 * 60)
        XCTAssertNil(state.match(in: plan, now: afterFirstLeft))
    }

    func testDepartedActivityEndsEvenWhenWalkIsNoLongerKnown() throws {
        let plan = Plan.sample(at: now, minutes: [8, 18])
        let r = try XCTUnwrap(CommuteRecommendation.make(plan: plan, now: now, bufferMinutes: 2))
        let state = CommuteActivity.ContentState(recommendation: r, plan: plan)
        var withoutWalk = plan
        withoutWalk.walkIsKnown = false
        XCTAssertEqual(state.refreshDecision(using: withoutWalk, now: state.departureAt), .end)
    }

    func testAgingAccessoryRecommendationIsSuppressed() {
        let options = WidgetOptions(recommends: true)
        let plan = Plan.sample(at: now, minutes: [20])
        XCTAssertTrue(options.canRecommend(plan: plan, at: now, isAccessory: true))
        XCTAssertFalse(options.canRecommend(plan: plan, at: now.addingTimeInterval(120), isAccessory: true))
        XCTAssertTrue(options.canRecommend(plan: plan, at: now.addingTimeInterval(120), isAccessory: false))
    }

    func testUncachedWidgetSnapshotDoesNotInventLiveTrains() {
        let entry = WidgetSnapshots.entry(options: WidgetOptions(stationID: "WTC"), cached: nil, isPreview: false, now: now)
        if case .plan = entry.state { XCTFail("Only gallery previews may show sample trains") }
        let preview = WidgetSnapshots.entry(options: WidgetOptions(stationID: "WTC"), cached: nil, isPreview: true, now: now)
        if case .plan(let plan) = preview.state { XCTAssertEqual(plan.stationID, "WTC") }
        else { XCTFail("Gallery previews should have sample content") }
    }

    func testExpiredOrUnknownWalkDoesNotRaiseSmartStackUrgency() {
        var plan = Plan.sample(at: now, walkMinutes: 4, minutes: [8])
        XCTAssertEqual(BoardEntry(date: now.addingTimeInterval(301), state: .plan(plan)).relevance?.score, 0)
        plan.walkIsKnown = false
        XCTAssertEqual(BoardEntry(date: now, state: .plan(plan)).relevance?.score, 0)
    }
}
