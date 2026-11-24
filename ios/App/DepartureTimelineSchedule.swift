import SwiftUI

/// Lazily extends the schedule if a cached board stays open during a long outage.
/// Each batch contains only the next hour's meaningful display changes.
struct DepartureTimelineSchedule: TimelineSchedule {
    let plan: Plan
    let bufferMinutes: Int
    let destinations: [Destination]

    func entries(from startDate: Date, mode: Mode) -> AnySequence<Date> {
        AnySequence {
            var batchStart = startDate
            var batch = AppUpdateSchedule.dates(for: plan, from: batchStart,
                bufferMinutes: bufferMinutes, showing: destinations).makeIterator()
            var last: Date?
            return AnyIterator {
                while true {
                    if let next = batch.next() {
                        if let last, next <= last { continue }
                        last = next
                        return next
                    }
                    batchStart.addTimeInterval(TimelineBuilder.horizon)
                    batch = AppUpdateSchedule.dates(for: plan, from: batchStart,
                        bufferMinutes: bufferMinutes, showing: destinations).makeIterator()
                }
            }
        }
    }
}
