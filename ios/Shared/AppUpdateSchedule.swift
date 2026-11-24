import Foundation

/// Redraw only when a displayed countdown, freshness label, or recommendation
/// changes. Network refreshes remain independent of this presentation schedule.
enum AppUpdateSchedule {
    static func dates(for plan: Plan, from now: Date, bufferMinutes: Int,
                      showing destinations: [Destination] = SharedStore.newportDestinations) -> [Date] {
        let end = now.addingTimeInterval(TimelineBuilder.horizon)
        var dates = Set(TimelineBuilder.redrawDates(for: plan, from: now,
            showing: destinations, bufferMinutes: bufferMinutes))
        var ageTick = plan.asOf.addingTimeInterval(60 + TimelineBuilder.tickSlack)
        if ageTick <= now {
            ageTick.addTimeInterval((floor(now.timeIntervalSince(ageTick) / 60) + 1) * 60)
        }
        while ageTick <= end {
            dates.insert(ageTick)
            ageTick.addTimeInterval(60)
        }
        return dates.sorted()
    }
}
