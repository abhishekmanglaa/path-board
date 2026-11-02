import Foundation

/// Decides when the widget redraws (free) and when it refetches (budgeted).
enum TimelineBuilder {
    /// Refetch at least this often while trains are listed. iOS caps actual reloads
    /// at roughly 40–70 a day, so asking for more just gets throttled.
    static let maxReloadInterval: TimeInterval = 15 * 60
    static let minReloadInterval: TimeInterval = 5 * 60
    static let horizon: TimeInterval = 60 * 60

    /// A shown minute count changes the instant its train is a whole number of
    /// minutes away; redrawing this long after that instant makes the new value
    /// land on the redraw instead of a minute late (counts round down).
    static let tickSlack: TimeInterval = 0.5

    /// Redraws are free, so place one exactly where any number on the board
    /// changes: each listed train's minute boundaries until it departs, plus the
    /// moment it departs and drops off the list. Nothing past the horizon.
    static func redrawDates(for plan: Plan, from now: Date) -> [Date] {
        let end = now.addingTimeInterval(horizon)
        var dates: Set<Date> = [now]
        for d in plan.upcoming(at: now) where d.date <= end {
            var t = d.date.addingTimeInterval(-60 * floor(d.date.timeIntervalSince(now) / 60) + tickSlack)
            if t <= now { t.addTimeInterval(60) }
            while t < d.date {
                dates.insert(t)
                t.addTimeInterval(60)
            }
            dates.insert(d.date.addingTimeInterval(tickSlack))
        }
        return dates.sorted()
    }

    /// Refetch as the list starts running dry (PATH only posts a couple of trains
    /// ahead per direction), but no sooner than `minReloadInterval` — a reload
    /// spent early is one missing later.
    static func reloadDate(for plan: Plan, from now: Date) -> Date {
        let upcoming = plan.upcoming(at: now)
        guard !upcoming.isEmpty else { return now.addingTimeInterval(minReloadInterval) }
        // When the second-to-last listed train leaves, only one remains: fetch more.
        let runningDry = upcoming[max(0, upcoming.count - 2)].date
        let target = min(now.addingTimeInterval(maxReloadInterval), runningDry)
        return max(target, now.addingTimeInterval(minReloadInterval))
    }
}
