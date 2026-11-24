import XCTest
@testable import PathHome

final class ServiceAlertTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func record(_ id: Int = 1, time: Double = 1_800_000_000,
                        state: String = "Open", title: String = "PATHAlert: Mechanical Problem",
                        body: String) -> [String: Any] {
        ["ebid": id, "messageid": id, "sentdate2": "/Date(\(Int(time * 1000)))/",
         "Subject": title, "SentMessage": body, "state": state]
    }

    private func feed(_ records: [[String: Any]]) throws -> ServiceAlertSnapshot {
        try ServiceAlertSnapshot.decode(JSONSerialization.data(withJSONObject: records), fetchedAt: now)
    }

    private func context(_ station: String, destinations: [String] = ["33"],
                         departures: [Departure] = []) -> ServiceAlertContext {
        ServiceAlertContext(station: Station.byID[station]!,
            destinations: Destination.newport.filter { destinations.contains($0.id) }, departures: departures)
    }

    func testOnlyAffectedRouteMatchesWhenOtherRoutesAreRunning() throws {
        let snapshot = try feed([record(body: "09:43 PM: NWK-WTC delayed. Crew at JSQ. JSQ-33, HOB-WTC running.")])
        XCTAssertEqual(snapshot.alerts.first?.routes, [.newarkWTC])
        XCTAssertTrue(snapshot.relevant(to: context("NWK"), at: now).alerts.count == 1)
        XCTAssertTrue(snapshot.relevant(to: context("33S"), at: now).alerts.isEmpty)
    }

    func testMixedStatusWithinOneSentenceDoesNotWarnUnaffectedRoutes() throws {
        let snapshot = try feed([record(body: "HOB-33 delayed, JSQ-33 and HOB-WTC running normally.")])
        XCTAssertEqual(snapshot.alerts.first?.routes, [.hoboken33])
        let prefixed = try feed([record(body: "Delays on NWK-WTC, JSQ-33 and HOB-WTC running normally.")])
        XCTAssertEqual(prefixed.alerts.first?.routes, [.newarkWTC])
    }

    func testWarningBadgeMatchesOnlyAffectedRow() throws {
        let departures = [
            Departure(date: now.addingTimeInterval(300), headsign: "Journal Square", lineColors: "FF9900"),
            Departure(date: now.addingTimeInterval(480), headsign: "Hoboken", lineColors: "4D92FB")
        ]
        let plan = Plan(stationID: "33S", walkSeconds: 240, departures: departures, computedAt: now,
                        originLatitude: 40.75, originLongitude: -73.99,
                        serviceAlerts: try feed([record(body: "HOB-33 running with delays. No delays on JSQ-33.")]))
        let rows = BoardSnapshot(plan: plan, at: now).rows
        XCTAssertNil(rows.first { $0.id == "JSQ–33" }?.alertScope)
        XCTAssertEqual(rows.first { $0.id == "HOB–33" }?.alertScope, "HOB–33")
    }

    func testLatestClosedIncidentRemovesEarlierOpenUpdateRegardlessOfOrder() throws {
        let open = record(time: now.timeIntervalSince1970 - 30, body: "HOB-33 delayed.")
        let closed = record(time: now.timeIntervalSince1970, state: "Closed", body: "HOB-33 resuming normal service.")
        for records in [[closed, open], [open, closed]] {
            XCTAssertTrue(try feed(records).alerts.isEmpty)
        }
    }

    func testNewerOpenIncidentReplacesOlderDetails() throws {
        let snapshot = try feed([
            record(time: now.timeIntervalSince1970 - 30, body: "HOB-33 delayed."),
            record(body: "HOB-33 suspended.")])
        XCTAssertEqual(snapshot.alerts.count, 1)
        XCTAssertEqual(snapshot.alerts.first?.message, "HOB-33 suspended.")
    }

    func testRouteAliasesAndSubjectRouteAreRecognized() throws {
        let snapshot = try feed([record(title: "NWK–WTC Service Update", body: "Use Platform B at Newark.")])
        XCTAssertEqual(snapshot.alerts.first?.routes, [.newarkWTC])
    }

    func testStationAdvisoryIgnoresAlternativeStationsInMessage() throws {
        let snapshot = try feed([record(title: "9 St Station and 23 St Station Overnight Advisory",
            body: "9 St and 23 St stations close nightly. Please use Christopher St, 14 St, or 33 St instead.")])
        XCTAssertEqual(snapshot.relevant(to: context("09S"), at: now).alerts.count, 1)
        XCTAssertTrue(snapshot.relevant(to: context("33S"), at: now).alerts.isEmpty)
    }

    func testElevatorAdvisoryIsStationSpecificRatherThanAllLinesMentioned() throws {
        let snapshot = try feed([record(title: "JSQ elevator between mezzanine and tracks 1 and 2 is out of service",
            body: "PATH Journal Square elevator for trains to 33 St and World Trade Center is unavailable.")])
        XCTAssertEqual(snapshot.relevant(to: context("JSQ"), at: now).alerts.count, 1)
        XCTAssertTrue(snapshot.relevant(to: context("33S"), at: now).alerts.isEmpty)
        XCTAssertTrue(snapshot.relevant(to: context("NEW", destinations: ["33"]), at: now).alerts.isEmpty)
        XCTAssertEqual(snapshot.relevant(to: context("NEW", destinations: ["JSQ"]), at: now).alerts.count, 1)
    }

    func testDirectHobokenAndViaHobokenAlertsAreDistinct() throws {
        let direct = try feed([record(body: "HOB-33 suspended. JSQ-33 via Hoboken running normally.")])
        let through = try feed([record(body: "JSQ-33 via Hoboken delayed.")])
        let combined = Departure(date: now.addingTimeInterval(600), headsign: "33rd Street via Hoboken", lineColors: "4D92FB,FF9900")
        XCTAssertTrue(direct.relevant(to: context("NEW", departures: [combined]), at: now).alerts.isEmpty)
        XCTAssertTrue(through.relevant(to: context("NEW", departures: []), at: now).alerts.isEmpty)
        XCTAssertEqual(through.relevant(to: context("NEW", departures: [combined]), at: now).alerts.count, 1)
    }

    func testSystemWideAlertsMatchButUnscopedSurveyDoesNot() throws {
        let snapshot = try feed([record(body: "All PATH lines are delayed due to a signal problem."),
            record(2, title: "PATH Wants Your Feedback", body: "Take our survey.")])
        XCTAssertEqual(snapshot.relevant(to: context("33S"), at: now).alerts.count, 1)
        XCTAssertEqual(snapshot.relevant(to: context("WTC"), at: now).alerts.count, 1)
    }

    func testAgeMarksEarlierAlertsThenUnavailableWithoutFalseAllClear() throws {
        let snapshot = try feed([record(body: "JSQ-33 delayed.")])
        XCTAssertFalse(snapshot.relevant(to: context("33S"), at: now).isStale)
        XCTAssertTrue(snapshot.relevant(to: context("33S"), at: now.addingTimeInterval(301)).isStale)
        let expired = snapshot.relevant(to: context("33S"), at: now.addingTimeInterval(901))
        XCTAssertTrue(expired.isUnavailable)
        XCTAssertTrue(expired.alerts.isEmpty)
    }

    func testEmptySuccessfulFeedClearsOldAlertsAndMalformedPayloadThrows() throws {
        XCTAssertTrue(try feed([]).alerts.isEmpty)
        XCTAssertThrowsError(try ServiceAlertSnapshot.decode(Data("{}".utf8), fetchedAt: now))
    }
}
