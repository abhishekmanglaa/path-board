import ActivityKit
import Foundation

@MainActor
final class CommuteActivityController: ObservableObject {
    static let shared = CommuteActivityController()
    @Published private(set) var isTracking = !Activity<CommuteActivity>.activities.isEmpty
    @Published var error: String?
    private var isStarting = false

    func start(_ recommendation: CommuteRecommendation, plan: Plan) async {
        guard !isStarting else { return }
        guard plan.freshness(at: Date()) == .fresh, plan.hasReliableWalk(at: Date()),
              recommendation.departure.date > Date() else {
            error = "Refresh the train prediction before starting tracking."
            return
        }
        isStarting = true
        defer { isStarting = false }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            error = "Live Activities are disabled. Enable them for PATH Home in Settings."
            return
        }
        await end()
        let state = CommuteActivity.ContentState(recommendation: recommendation, plan: plan)
        do {
            _ = try Activity.request(attributes: CommuteActivity(stationID: plan.stationID,
                        stationName: plan.station.name, headsign: recommendation.departure.headsign),
                        content: ActivityContent(state: state, staleDate: state.staleAt), pushType: nil)
            isTracking = true
            error = nil
        } catch { self.error = "Couldn't start the Live Activity. Please try again." }
    }

    func update(using plan: Plan) async {
        for activity in Activity<CommuteActivity>.activities where activity.attributes.stationID == plan.stationID {
            let old = activity.content.state
            let train: Departure
            switch old.refreshDecision(using: plan, now: Date()) {
            case .end: await activity.end(nil, dismissalPolicy: .immediate); continue
            case .keep: continue
            case .update(let matched): train = matched
            }
            let needed = Double((plan.walkMinutes + old.bufferMinutes) * 60)
            let r = CommuteRecommendation(departure: train, leaveAt: train.date.addingTimeInterval(-needed),
                walkMinutes: plan.walkMinutes, bufferMinutes: old.bufferMinutes, skippedTightTrain: false)
            let state = CommuteActivity.ContentState(recommendation: r, plan: plan)
            await activity.update(ActivityContent(state: state, staleDate: state.staleAt))
        }
        isTracking = !Activity<CommuteActivity>.activities.isEmpty
    }

    func end() async {
        for activity in Activity<CommuteActivity>.activities { await activity.end(nil, dismissalPolicy: .immediate) }
        isTracking = false
    }

    func syncStatus() { isTracking = !Activity<CommuteActivity>.activities.isEmpty }
}
