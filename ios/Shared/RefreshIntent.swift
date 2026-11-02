import AppIntents
import CoreLocation
import WidgetKit

/// The widget's refresh button. Runs in the widget's process: it computes a
/// fresh plan (skipping the "reuse a plan under a minute old" shortcut, since a
/// tap means "get me new times"), saves it, and WidgetKit reloads the timeline
/// right after `perform` returns — which then reuses this plan instead of
/// fetching again.
struct RefreshTrainsIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh Trains"
    static var description = IntentDescription("Fetches the latest PATH departures for the widget.")
    static var isDiscoverable = false

    func perform() async throws -> some IntentResult {
        let manager = CLLocationManager()
        let fix = manager.isAuthorizedForWidgetUpdates ? manager.location : nil
        if let here = SharedStore.freshestLocation(fix) {
            SharedStore.lastPlan = try? await Planner.plan(from: here, forceFresh: true)
        }
        return .result()
    }
}
