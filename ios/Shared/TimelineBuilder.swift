import Foundation

/// Decides when cached widget content changes and when a network reload is due.
enum TimelineBuilder {
    /// Requested refresh cadence; WidgetKit controls the actual reload budget.
    static let maxReloadInterval: TimeInterval = 15 * 60
    static let minReloadInterval: TimeInterval = 10 * 60
    static let horizon: TimeInterval = 60 * 60

    /// A shown minute count changes the instant its train is a whole number of
    /// minutes away; redrawing this long after that instant makes the new value
    /// land on the redraw instead of a minute late.
    static let tickSlack: TimeInterval = 0.5

    /// Timeline entries need no network request. Place one where a displayed value
    /// changes: each listed train's minute boundaries until it departs, plus the
    /// moment it departs and drops off the list. Nothing past the horizon.
    static func redrawDates(for plan: Plan, from now: Date,
                            showing destinations: [Destination] = SharedStore.newportDestinations,
                            bufferMinutes: Int = SharedStore.bufferMinutes) -> [Date] {
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
            if plan.hasReliableWalk(at: now) {
                let leave = d.date.addingTimeInterval(-Double((plan.walkMinutes + bufferMinutes) * 60))
                if leave > now && leave <= end { dates.insert(leave) }
                if leave.addingTimeInterval(tickSlack) > now && leave.addingTimeInterval(tickSlack) <= end {
                    dates.insert(leave.addingTimeInterval(tickSlack))
                }
            }
        }
        var boundaries = [plan.asOf.addingTimeInterval(120), plan.asOf.addingTimeInterval(300),
                          plan.walkMeasuredAt.addingTimeInterval(Plan.walkAdviceAge + tickSlack),
                          plan.walkMeasuredAt.addingTimeInterval(Plan.savedWalkAge)]
        if let alerts = plan.serviceAlerts {
            boundaries += [alerts.fetchedAt.addingTimeInterval(ServiceAlertSnapshot.refreshInterval),
                           alerts.fetchedAt.addingTimeInterval(ServiceAlertSnapshot.validity)]
        }
        for boundary in boundaries where boundary > now && boundary <= end {
            dates.insert(boundary)
        }
        return dates.sorted()
    }

    /// Refetch as the posted trains run out (PATH only posts a train or two ahead
    /// per direction; timetabled ones fill in but aren't live), but no sooner than
    /// `minReloadInterval` — a reload spent early is one missing later.
    static func reloadDate(for plan: Plan, from now: Date) -> Date {
        let upcoming = plan.upcoming(at: now).filter { !$0.scheduled }
        guard !upcoming.isEmpty else { return now.addingTimeInterval(maxReloadInterval) }
        // When the second-to-last listed train leaves, only one remains: fetch more.
        let runningDry = upcoming[max(0, upcoming.count - 2)].date
        let target = min(now.addingTimeInterval(maxReloadInterval), runningDry)
        return max(target, now.addingTimeInterval(minReloadInterval))
    }
}
