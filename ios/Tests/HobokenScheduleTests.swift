import XCTest
@testable import PathHome

final class HobokenScheduleTests: XCTestCase {
    private func date(_ clock: String, day: String = "2026-11-03") -> Date {
        ISO8601DateFormatter().date(from: "\(day)T\(clock):00-05:00")!
    }

    private func board(_ live: [Departure], station: String = "33S", at now: Date) -> BoardSnapshot {
        let s = Station.byID[station]!
        let plan = Plan(stationID: station, walkSeconds: 240,
                        departures: Planner.withTimetable(live, at: s, now: now), computedAt: now,
                        originLatitude: s.latitude, originLongitude: s.longitude)
        return BoardSnapshot(plan: plan, at: now)
    }

    func testHobokenHasLiveTrainAndNextTwoTimetableDepartures() throws {
        let now = date("17:00")
        let live = Departure(date: date("17:06").addingTimeInterval(30), headsign: "Hoboken", lineColors: "4D92FB")
        let row = try XCTUnwrap(board([live], at: now).rows.first { $0.id == "HOB–33" })
        XCTAssertEqual(row.trains.count, 3)
        XCTAssertEqual(row.trains.map(\.scheduled), [false, true, true])
        XCTAssertEqual(row.trains.map(\.departure.date), ["17:06", "17:12", "17:18"].map { date($0).addingTimeInterval(30) })
        XCTAssertEqual(row.tiny, "HOB")
    }

    func testHobokenRowSurvivesExpiryAndNextFeedOmission() throws {
        let now = date("17:00")
        let hob = Departure(date: date("17:06"), headsign: "Hoboken", lineColors: "4D92FB")
        let jsq = Departure(date: date("17:06"), headsign: "Journal Square", lineColors: "FF9900")
        let initial = board([hob, jsq], at: now)
        let after = date("17:07")
        XCTAssertNotNil(initial.rows.first { $0.id == "HOB–33" })
        let next = try XCTUnwrap(board([jsq], at: after).rows.first { $0.id == "HOB–33" })
        XCTAssertEqual(next.trains.count, 3)
        XCTAssertTrue(next.trains.allSatisfy(\.scheduled))
        XCTAssertEqual(next.next.departure.date, date("17:12"))
    }

    func testExistingTimelineKeepsHobokenAfterLastLiveTrainLeaves() throws {
        let now = date("17:00"), s = Station.byID["33S"]!
        let hob = Departure(date: date("17:06"), headsign: "Hoboken", lineColors: "4D92FB")
        let plan = Plan(stationID: s.id, walkSeconds: 240,
                        departures: Planner.withTimetable([hob], at: s, now: now), computedAt: now,
                        originLatitude: s.latitude, originLongitude: s.longitude)
        let row = try XCTUnwrap(BoardSnapshot(plan: plan, at: date("17:07")).rows.first { $0.id == "HOB–33" })
        XCTAssertEqual(row.trains.count, 3)
        XCTAssertTrue(row.trains.allSatisfy(\.scheduled))
    }

    func testManhattanRowsKeepTheirOrderWhenSoonestTrainChanges() {
        let now = date("17:00")
        let hob = Departure(date: date("17:04"), headsign: "Hoboken", lineColors: "4D92FB")
        let jsq = Departure(date: date("17:06"), headsign: "Journal Square", lineColors: "FF9900")
        XCTAssertEqual(board([hob, jsq], at: now).rows.map(\.id), ["JSQ–33", "HOB–33"])
        let laterHob = Departure(date: date("17:14"), headsign: "Hoboken", lineColors: "4D92FB")
        XCTAssertEqual(board([jsq, laterHob], at: now).rows.map(\.id), ["JSQ–33", "HOB–33"])
    }

    func testEachManhattanStationUsesItsOwnHobokenDepartureTime() throws {
        for (station, clock) in [("33S", "17:06"), ("23S", "17:01"), ("14S", "17:02"), ("09S", "17:04"), ("CHR", "17:05")] {
            let row = try XCTUnwrap(board([], station: station, at: date("17:00")).rows.first { $0.id == "HOB–33" }, station)
            XCTAssertEqual(row.next.departure.date, date(clock), station)
            XCTAssertEqual(row.trains.count, 3, station)
        }
    }

    func testNoDedicatedHobokenTrainsAreInventedOvernight() {
        XCTAssertFalse(board([], at: date("01:00")).rows.contains { $0.id == "HOB–33" })
        XCTAssertFalse(board([], at: date("23:20")).rows.contains { $0.id == "HOB–33" })
    }

    func testHobokenScheduleDoesNotLeakToOtherStations() {
        XCTAssertFalse(board([], station: "NEW", at: date("17:00")).rows.contains { $0.id == "HOB–33" })
        XCTAssertTrue(board([], station: "NWK", at: date("17:00")).rows.isEmpty)
    }

    func testWeekendHobokenUsesPublishedDedicatedService() throws {
        for day in ["2026-11-07", "2026-11-08"] {
            let row = try XCTUnwrap(board([], at: date("13:00", day: day)).rows.first { $0.id == "HOB–33" })
            XCTAssertEqual(row.trains.count, 3)
            XCTAssertTrue(row.trains.allSatisfy(\.scheduled))
            XCTAssertEqual(row.trains.map(\.departure.date), ["13:05", "13:15", "13:25"].map { date($0, day: day) })
        }
    }

    func testLastPublishedTrainDoesNotProduceInventedLaterTrains() throws {
        let row = try XCTUnwrap(board([], at: date("22:46")).rows.first { $0.id == "HOB–33" })
        XCTAssertEqual(row.trains.count, 1)
        XCTAssertEqual(row.next.departure.date, date("22:47"))
        XCTAssertFalse(board([], at: date("22:48")).rows.contains { $0.id == "HOB–33" })
    }

    func testUnevenWeekendGapUsesActualSlotsInsteadOfFlatHeadway() throws {
        let day = "2026-11-07"
        let now = date("20:54", day: day)
        let hob = Departure(date: date("20:55", day: day).addingTimeInterval(30), headsign: "Hoboken", lineColors: "4D92FB")
        let row = try XCTUnwrap(board([hob], at: now).rows.first { $0.id == "HOB–33" })
        XCTAssertEqual(row.trains.map(\.departure.date), ["20:55", "21:17", "21:27"].map { date($0, day: day).addingTimeInterval(30) })
    }

    func testUnsortedPostedTrainsAnchorToTheLastDeparture() throws {
        let live = ["17:12", "17:06"].map { Departure(date: date($0), headsign: "Hoboken", lineColors: "4D92FB") }
        let row = try XCTUnwrap(board(live, at: date("17:00")).rows.first { $0.id == "HOB–33" })
        XCTAssertEqual(row.trains.map(\.departure.date), ["17:06", "17:12", "17:18"].map { date($0) })
    }

    func testUnscheduledAfterMidnightTrainDoesNotInventOvernightService() throws {
        let now = date("23:58")
        let extra = Departure(date: date("00:02", day: "2026-11-04"), headsign: "Hoboken", lineColors: "4D92FB")
        let row = try XCTUnwrap(board([extra], at: now).rows.first { $0.id == "HOB–33" })
        XCTAssertEqual(row.trains.map(\.scheduled), [false])
        XCTAssertEqual(row.next.departure, extra)
    }
}
