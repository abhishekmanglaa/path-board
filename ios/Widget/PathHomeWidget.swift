import CoreLocation
import SwiftUI
import WidgetKit

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> BoardEntry {
        BoardEntry(date: .now, state: .plan(.sample(at: .now)))
    }

    func getSnapshot(in context: Context, completion: @escaping (BoardEntry) -> Void) {
        let plan = context.isPreview ? .sample(at: .now) : (SharedStore.lastPlan ?? .sample(at: .now))
        completion(BoardEntry(date: .now, state: .plan(plan)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BoardEntry>) -> Void) {
        Task {
            completion(await timeline())
        }
    }

    private func timeline() async -> Timeline<BoardEntry> {
        let now = Date()
        let manager = CLLocationManager()
        // The widget can read the system's cached fix when the app has location
        // access and NSWidgetWantsLocation is set; the app also stores fixes it
        // gets from background wakeups. Use whichever is newer.
        let widgetFix = manager.isAuthorizedForWidgetUpdates ? manager.location : nil
        guard let here = SharedStore.freshestLocation(widgetFix) else {
            return Timeline(entries: [BoardEntry(date: now, state: .needsLocation)],
                            policy: .after(now.addingTimeInterval(TimelineBuilder.maxReloadInterval)))
        }

        do {
            let plan = try await Planner.plan(from: here)
            SharedStore.lastPlan = plan
            let entries = TimelineBuilder.redrawDates(for: plan, from: now)
                .map { BoardEntry(date: $0, state: .plan(plan)) }
            return Timeline(entries: entries, policy: .after(TimelineBuilder.reloadDate(for: plan, from: now)))
        } catch {
            let stale = SharedStore.lastPlan
            let entries = stale.map { plan in
                TimelineBuilder.redrawDates(for: plan, from: now)
                    .map { BoardEntry(date: $0, state: .failed(message: error.localizedDescription, stale: plan)) }
            } ?? [BoardEntry(date: now, state: .failed(message: error.localizedDescription, stale: nil))]
            return Timeline(entries: entries, policy: .after(now.addingTimeInterval(TimelineBuilder.minReloadInterval)))
        }
    }
}

struct PathHomeWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BoardEntry

    var body: some View {
        BoardView(entry: entry, family: family)
            .widgetURL(entry.deepLink)
            .containerBackground(for: .widget) {
                Color(uiColor: .systemBackground)
            }
    }
}

struct PathHomeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PathHome", provider: Provider()) { entry in
            PathHomeWidgetView(entry: entry)
        }
        .configurationDisplayName("Train Home")
        .description("Walk time to the nearest PATH station and its next trains home.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline, .accessoryCircular])
    }
}

/// The same board as rings on smoked glass. When both widgets reload together the
/// second reuses the first's plan (`Planner.reuseWindow`), so it costs no extra fetch.
struct PathHomeGlassWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PathHomeGlass", provider: Provider()) { entry in
            PathHomeGlassView(entry: entry)
        }
        .configurationDisplayName("Train Rings")
        .description("Walk time and the next train in each direction, as rings.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct PathHomeGlassView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BoardEntry

    var body: some View {
        GlassBoardView(entry: entry, family: family)
            .environment(\.colorScheme, .dark)
            .widgetURL(entry.deepLink)
            .containerBackground(for: .widget) { GlassBackground() }
    }
}

@main
struct PathHomeWidgets: WidgetBundle {
    var body: some Widget {
        PathHomeWidget()
        PathHomeGlassWidget()
    }
}
