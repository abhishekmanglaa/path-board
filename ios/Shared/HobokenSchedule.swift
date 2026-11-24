import Foundation

/// The direct HOB–33 service has its own published timetable: it never passes
/// Newport and cannot be projected from Newport's Hoboken-bound train times.
enum HobokenSchedule {
    /// An extra/disrupted live train may be far from any published service.
    /// Never shift a morning timetable hours earlier to follow an overnight train.
    static let maxAnchorOffset: TimeInterval = 15 * 60
    /// Minutes after the departure from 33rd Street, verified against every row
    /// of the published weekday, Saturday and Sunday timetables.
    static let stationOffsets = ["33S": 0, "23S": 1, "14S": 2, "09S": 4, "CHR": 5]

    static func slots(at station: Station, on day: Date) -> [Date] {
        guard let offset = stationOffsets[station.id] else { return [] }
        let calendar = NewportSchedule.calendar
        let midnight = calendar.startOfDay(for: day)
        return (table[NewportSchedule.dayType(day)] ?? []).compactMap { minute in
            calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: midnight)?
                .addingTimeInterval(Double(offset) * 60)
        }
    }

    static func projected(after live: [Departure], at station: Station, now: Date) -> [Departure] {
        guard stationOffsets[station.id] != nil else { return [] }
        let posted = live.filter { $0.headsign.lowercased().hasPrefix("hoboken") && $0.line.shortName == "HOB–33" }
            .sorted { $0.date < $1.date }
        let anchor = posted.last
        let reference = anchor?.date ?? now
        let calendar = NewportSchedule.calendar
        let today = slots(at: station, on: reference)
        let tomorrow = slots(at: station, on: calendar.date(byAdding: .day, value: 1, to: reference)!)
        let departures: [Date]
        if let anchor, let nearest = today.min(by: { abs($0.timeIntervalSince(anchor.date)) < abs($1.timeIntervalSince(anchor.date)) }),
           abs(anchor.date.timeIntervalSince(nearest)) <= maxAnchorOffset {
            let delta = anchor.date.timeIntervalSince(nearest)
            departures = (today + tomorrow).filter { $0 > nearest }.map { $0.addingTimeInterval(delta) }
        } else {
            departures = today + tomorrow
        }
        let end = now.addingTimeInterval(NewportSchedule.lookahead)
        return departures.filter { $0 > now && $0 <= end }.map {
            Departure(date: $0, headsign: "Hoboken", lineColors: "4D92FB", scheduled: true)
        }
    }
}
