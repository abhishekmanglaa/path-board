import ActivityKit
import AppIntents

/// LiveActivityIntent executes in the app process, so it belongs to both targets.
struct EndCommuteIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "End train tracking"
    static var isDiscoverable = false
    func perform() async throws -> some IntentResult {
        for activity in Activity<CommuteActivity>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        return .result()
    }
}
