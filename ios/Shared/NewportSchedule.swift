import Foundation

/// Newport's timetable, used to show the trains after the ones PATH has posted,
/// at Newport and (shifted by the ride) at stations on lines through it.
/// The live feed lists about one train ahead per direction; the rest come from
/// here, shifted by however early or late the posted train is running (the same
/// projection the kiosk uses).
enum NewportSchedule {
    enum DayType { case weekday, sat, sun }

    /// How far ahead scheduled trains are projected.
    static let lookahead: TimeInterval = 2 * 60 * 60
    /// For a line with no timetable that day (WTC has none on weekends, though it
    /// runs), the gap assumed after the posted train.
    static let fallbackHeadway: TimeInterval = 20 * 60

    static var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    static func dayType(_ date: Date) -> DayType {
        switch calendar.component(.weekday, from: date) {
        case 1: return .sun
        case 7: return .sat
        default: return .weekday
        }
    }

    /// Wall-clock minute of the day, what the timetable is keyed by. Not seconds
    /// since midnight, which is off by an hour on DST change days.
    static func wallMinutes(_ date: Date) -> Double {
        let c = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        return Double(c.hour! * 60 + c.minute!) + (Double(c.second!) + Double(c.nanosecond!) / 1e9) / 60
    }

    /// Scheduled departures on `day`'s calendar date, `lead` earlier for a
    /// station up the line from Newport.
    static func slots(_ key: String, on day: Date, lead: TimeInterval = 0) -> [Date] {
        let midnight = calendar.startOfDay(for: day)
        return (table[dayType(day)]?[key] ?? []).compactMap { m in
            calendar.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: midnight)?.addingTimeInterval(-lead)
        }
    }

    /// Slots strictly after `date`, today then tomorrow.
    static func slots(_ key: String, after date: Date, lead: TimeInterval = 0) -> [Date] {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: date)!
        return (slots(key, on: date, lead: lead) + slots(key, on: tomorrow, lead: lead)).filter { $0 > date }
    }

    /// Trains to show after the posted ones (`live`, soonest first) for one
    /// direction, up to `lookahead` past `now`.
    ///
    /// The last posted train is matched to its nearest timetable slot; that offset
    /// (running early or late) carries onto the slots that follow. With nothing
    /// posted, the timetable is used as is.
    static func projected(_ key: String, after live: [Date], now: Date, lead: TimeInterval = 0) -> [Date] {
        let end = now.addingTimeInterval(lookahead)
        let next: [Date]
        if let anchor = live.last {
            let today = slots(key, on: anchor, lead: lead)
            if let nearest = today.min(by: { abs($0.timeIntervalSince(anchor)) < abs($1.timeIntervalSince(anchor)) }) {
                let delta = anchor.timeIntervalSince(nearest)
                next = slots(key, after: nearest, lead: lead).map { $0.addingTimeInterval(delta) }
            } else {
                next = (1...Int(lookahead / fallbackHeadway)).map { anchor.addingTimeInterval(Double($0) * fallbackHeadway) }
            }
        } else {
            next = slots(key, after: now, lead: lead)
        }
        return next.filter { $0 > now && $0 <= end }
    }
}
