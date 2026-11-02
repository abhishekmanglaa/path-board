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
    /// changes: each catchable train's minute boundaries while it can still be
    /// caught, plus the moment it stops being catchable and the card moves on.
    /// Nothing ticks past the last catchable train or the horizon.
    static func redrawDates(for plan: Plan, from now: Date) -> [Date] {
        let end = now.addingTimeInterval(horizon)
        var dates: Set<Date> = [now]
        for d in plan.catchable(at: now) {
            let missed = plan.leaveBy(d).addingTimeInterval(1)
            let until = min(missed, end)
            var t = d.date.addingTimeInterval(-60 * floor(d.date.timeIntervalSince(now) / 60) + tickSlack)
            if t <= now { t.addTimeInterval(60) }
            while t < until {
                dates.insert(t)
                t.addTimeInterval(60)
            }
            if missed <= end { dates.insert(missed) }
        }
        // A "just missed" train is named until it actually leaves.
        for d in plan.departures where d.date > now && d.date <= end && plan.leaveBy(d) < now {
            dates.insert(d.date.addingTimeInterval(1))
        }
        return dates.sorted()
    }

    /// Refetch before the board would run out of catchable trains, but no sooner
    /// than `minReloadInterval` (a reload spent early is one missing later).
    static func reloadDate(for plan: Plan, from now: Date) -> Date {
        let catchable = plan.catchable(at: now)
        // Nothing left to count down to: refetch as soon as the floor allows.
        if catchable.isEmpty { return now.addingTimeInterval(minReloadInterval) }
        var target = now.addingTimeInterval(maxReloadInterval)
        // When only one catchable train remains, refetch as the one before the
        // last becomes uncatchable, so there's still something to show meanwhile.
        if catchable.count >= 2 {
            target = min(target, plan.leaveBy(catchable[catchable.count - 2]))
        } else {
            target = min(target, plan.leaveBy(catchable[0]))
        }
        return max(target, now.addingTimeInterval(minReloadInterval))
    }
}
