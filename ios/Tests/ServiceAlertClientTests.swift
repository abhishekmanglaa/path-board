import XCTest
@testable import PathHome

final class ServiceAlertClientTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    actor Probe {
        var calls = 0
        var fail = false
        func request() async throws -> Data {
            calls += 1
            try await Task.sleep(for: .milliseconds(10))
            if fail { throw URLError(.notConnectedToInternet) }
            return Data("[]".utf8)
        }
        func setFailure() { fail = true }
    }

    func testFreshCacheAvoidsNetworkAndConcurrentRequestsCoalesce() async {
        let probe = Probe()
        let client = ServiceAlertClient(fetch: { try await probe.request() })
        let cached = ServiceAlertSnapshot(fetchedAt: now, alerts: [])
        let value = await client.snapshot(cached: cached, at: now)
        XCTAssertEqual(value, cached)
        let initialCalls = await probe.calls
        XCTAssertEqual(initialCalls, 0)
        let fetched = await withTaskGroup(of: ServiceAlertSnapshot?.self) { group in
            for _ in 0..<10 {
                group.addTask { await client.snapshot(cached: cached, at: self.now.addingTimeInterval(301)) }
            }
            var values: [ServiceAlertSnapshot?] = []
            for await value in group { values.append(value) }
            return values
        }
        XCTAssertEqual(fetched.count, 10)
        XCTAssertTrue(fetched.allSatisfy { $0?.fetchedAt == now.addingTimeInterval(301) })
        let totalCalls = await probe.calls
        XCTAssertEqual(totalCalls, 1)
    }

    func testFailurePreservesOldSnapshotWithoutRefreshingItsTimestampOrRetryStorm() async {
        let probe = Probe()
        await probe.setFailure()
        let client = ServiceAlertClient(fetch: { try await probe.request() })
        let cached = ServiceAlertSnapshot(fetchedAt: now.addingTimeInterval(-301), alerts: [])
        let first = await client.snapshot(cached: cached, at: now)
        XCTAssertEqual(first, cached)
        _ = await client.snapshot(cached: cached, at: now.addingTimeInterval(30))
        let initialCalls = await probe.calls
        XCTAssertEqual(initialCalls, 1)
        _ = await client.snapshot(cached: cached, at: now.addingTimeInterval(300))
        let totalCalls = await probe.calls
        XCTAssertEqual(totalCalls, 2)
    }

    func testSuccessfulEmptyFeedReplacesPreviousAlerts() async {
        let probe = Probe()
        let client = ServiceAlertClient(fetch: { try await probe.request() })
        let alert = ServiceAlert(id: "1", title: "JSQ–33 delayed", message: "Delay", publishedAt: now,
            routes: [.journalSquare33], stationIDs: [], systemWide: false)
        let old = ServiceAlertSnapshot(fetchedAt: now.addingTimeInterval(-301), alerts: [alert])
        let result = await client.snapshot(cached: old, at: now)
        XCTAssertEqual(result?.alerts, [])
        XCTAssertEqual(result?.fetchedAt, now)
    }
}
