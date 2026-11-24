import XCTest
@testable import PathHome

@MainActor
final class RefreshTests: XCTestCase {
    func testSlowOldRequestCannotOverwriteANewerStation() async throws {
        let requests = LatestPlanRequest()
        var finishOld: CheckedContinuation<Plan, Never>?
        let old = Task {
            try await requests.run {
                await withCheckedContinuation { finishOld = $0 }
            }
        }
        while finishOld == nil { await Task.yield() }
        let fresh = try await requests.run { .sample(at: Date(), stationID: "NEW") }
        XCTAssertEqual(fresh?.stationID, "NEW")
        finishOld?.resume(returning: .sample(at: Date(), stationID: "WTC"))
        let obsolete = try await old.value
        XCTAssertNil(obsolete)
    }

    func testCancellationDiscardsEvenAnUncooperativeRequest() async throws {
        let requests = LatestPlanRequest()
        var finish: CheckedContinuation<Plan, Never>?
        let pending = Task { try await requests.run { await withCheckedContinuation { finish = $0 } } }
        while finish == nil { await Task.yield() }
        requests.cancel()
        finish?.resume(returning: .sample(at: Date()))
        let result = try await pending.value
        XCTAssertNil(result)
    }

    func testOnlyLatestErrorIsReportedAndRecoveryWorks() async throws {
        let requests = LatestPlanRequest()
        do {
            _ = try await requests.run { throw PlanError.feedUnavailable }
            XCTFail("Current request must report its error")
        } catch { XCTAssertEqual(error as? PlanError, .feedUnavailable) }
        let recovered = try await requests.run { .sample(at: Date()) }
        XCTAssertNotNil(recovered)
    }

    func testForegroundPollingStopsWhenCancelled() async {
        let poller = ForegroundPoller()
        var calls = 0
        poller.start(interval: .milliseconds(10)) { calls += 1 }
        try? await Task.sleep(for: .milliseconds(35))
        poller.stop()
        let stoppedAt = calls
        XCTAssertGreaterThan(stoppedAt, 0)
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(calls, stoppedAt)
    }

    func testImmediateRefreshDoesNotStartAfterLeavingForeground() async {
        let poller = ForegroundPoller()
        var calls = 0
        poller.start(interval: .seconds(30), immediately: true) { calls += 1 }
        poller.stop()
        await Task.yield()
        XCTAssertEqual(calls, 0)
    }

    func testPollerReadsDelayAgainAfterEachRequest() async {
        let poller = ForegroundPoller()
        var calls = 0
        var delaysRead = 0
        let completed = expectation(description: "Second request finished")
        poller.start(immediately: true, nextInterval: {
            delaysRead += 1
            return calls < 2 ? .milliseconds(1) : .seconds(60)
        }) {
            calls += 1
            if calls == 2 { completed.fulfill() }
        }
        await fulfillment(of: [completed], timeout: 1)
        try? await Task.sleep(for: .milliseconds(20))
        poller.stop()
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(delaysRead, 2)
    }
}
