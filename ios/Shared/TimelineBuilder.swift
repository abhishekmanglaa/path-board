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
    /// land on the redraw instead of a minute late.
    static let tickSlack: TimeInterval = 0.5

    /// Redraws are free, so place one exactly where any number on the board
    /// changes: each listed train's minute boundaries until it departs, plus the
    /// moment it departs and drops off the list. Nothing past the horizon.
    static func redrawDates(for plan: Plan, from now: Date,
                            showing destinations: [Destination] = SharedStore.newportDestinations) -> [Date] {
        let end = now.addingTimeInterval(horizon)
        var dates: Set<Date> = [now]
        let shown = plan.upcoming(at: now).filter { d in
            !plan.station.isHome || destinations.contains { $0.includes(d) }
        }
        // A shown train may leave after the horizon (timetabled ones run two hours
        // out) and still needs its count kept current until then.
        for d in shown {
            var t = d.date.addingTimeInterval(-60 * floor(d.date.timeIntervalSince(now) / 60) + tickSlack)
            if t <= now { t.addTimeInterval(60) }
            while t < d.date && t <= end {
                dates.insert(t)
                t.addTimeInterval(60)
            }
            if d.date <= end { dates.insert(d.date.addingTimeInterval(tickSlack)) }
        }
        return dates.sorted()
    }

    /// Refetch as the posted trains run out (PATH only posts a train or two ahead
    /// per direction; timetabled ones fill in but aren't live), but no sooner than
    /// `minReloadInterval` — a reload spent early is one missing later.
    static func reloadDate(for plan: Plan, from now: Date) -> Date {
        let upcoming = plan.upcoming(at: now).filter { !$0.scheduled }
        guard !upcoming.isEmpty else { return now.addingTimeInterval(minReloadInterval) }
        // When the second-to-last listed train leaves, only one remains: fetch more.
        let runningDry = upcoming[max(0, upcoming.count - 2)].date
        let target = min(now.addingTimeInterval(maxReloadInterval), runningDry)
        return max(target, now.addingTimeInterval(minReloadInterval))
    }
}
