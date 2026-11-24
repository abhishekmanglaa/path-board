import ActivityKit
import Foundation

struct CommuteActivity: ActivityAttributes {
    let stationID: String
    let stationName: String
    let headsign: String

    struct ContentState: Codable, Hashable {
        enum Status { case ready, checkApp, departed }
        enum RefreshDecision: Equatable { case end, keep, update(Departure) }
        var departureAt: Date
        var leaveAt: Date
        var predictionAt: Date
        var walkMinutes: Int
        var bufferMinutes: Int
        var scheduled: Bool
        var headsign: String

        init(recommendation: CommuteRecommendation, plan: Plan) {
            departureAt = recommendation.departure.date
            leaveAt = recommendation.leaveAt
            predictionAt = plan.asOf
            walkMinutes = recommendation.walkMinutes
            bufferMinutes = recommendation.bufferMinutes
            scheduled = recommendation.departure.scheduled
            headsign = recommendation.departure.headsign
        }

        var staleAt: Date { min(predictionAt.addingTimeInterval(120), departureAt) }
        func status(at now: Date) -> Status {
            now >= departureAt ? .departed : now >= staleAt ? .checkApp : .ready
        }

        func refreshDecision(using plan: Plan, now: Date) -> RefreshDecision {
            if now >= departureAt { return .end }
            guard plan.freshness(at: now) == .fresh, plan.hasReliableWalk(at: now),
                  let departure = match(in: plan, now: now) else { return .keep }
            return .update(departure)
        }

        /// Match only this train, allowing a small revision. Do not silently
        /// switch the activity to the next service when the selected train leaves.
        func match(in plan: Plan, now: Date) -> Departure? {
            guard now < departureAt else { return nil }
            return plan.upcoming(at: now).filter {
                $0.headsign == headsign && abs($0.date.timeIntervalSince(departureAt)) <= 90
            }.min { abs($0.date.timeIntervalSince(departureAt)) < abs($1.date.timeIntervalSince(departureAt)) }
        }
    }
}
