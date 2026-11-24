import CoreLocation
import SwiftUI
import WidgetKit

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> BoardEntry {
        BoardEntry(date: .now, state: .plan(.sample(at: .now)))
    }

    func snapshot(for configuration: BoardConfigurationIntent, in context: Context) async -> BoardEntry {
        let options = configuration.options
        return WidgetSnapshots.entry(options: options, cached: SharedStore.plan(for: options.cacheKey),
                                     isPreview: context.isPreview, now: .now)
    }

    func timeline(for configuration: BoardConfigurationIntent, in context: Context) async -> Timeline<BoardEntry> {
        let options = configuration.options
        do {
            let refreshed = try await WidgetPlanRefresh.load(options: options)
            let now = Date()
            guard let plan = refreshed else {
                return Timeline(entries: [BoardEntry(date: now, state: .needsLocation, options: options)],
                                policy: .after(now.addingTimeInterval(TimelineBuilder.maxReloadInterval)))
            }
            return Timeline(entries: entries(plan, now: now, options: options),
                            policy: .after(TimelineBuilder.reloadDate(for: plan, from: now)))
        } catch PlanError.farFromPATH {
            let now = Date()
            return Timeline(entries: [BoardEntry(date: now, state: .farAway, options: options)],
                            policy: .after(now.addingTimeInterval(TimelineBuilder.maxReloadInterval)))
        } catch {
            let now = Date()
            let cached = SharedStore.plan(for: options.cacheKey)
            let dates = cached.map { TimelineBuilder.redrawDates(for: $0, from: now, showing: options.destinations) } ?? [now]
            let entries = dates.map {
                BoardEntry(date: $0, state: .failed(message: "Couldn't update trains", stale: cached), options: options)
            }
            return Timeline(entries: entries, policy: .after(now.addingTimeInterval(TimelineBuilder.maxReloadInterval)))
        }
    }

    private func entries(_ plan: Plan, now: Date, options: WidgetOptions) -> [BoardEntry] {
        TimelineBuilder.redrawDates(for: plan, from: now, showing: options.destinations)
            .map { BoardEntry(date: $0, state: .plan(plan), options: options) }
    }
}

struct PathHomeWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BoardEntry
    var body: some View {
        ConfiguredBoard(entry: entry, family: family)
            .widgetURL(entry.deepLink)
            .containerBackground(for: .widget) { Color(uiColor: .systemBackground) }
    }
}

struct PathHomeWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "PathHome", intent: BoardConfigurationIntent.self, provider: Provider()) { entry in
            PathHomeWidgetView(entry: entry)
        }
        .configurationDisplayName("Train Home")
        .description("Departures or when to leave, for your location or a chosen station.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline, .accessoryCircular])
    }
}

struct PathHomeGlassWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "PathHomeGlass", intent: BoardConfigurationIntent.self, provider: Provider()) { entry in
            PathHomeGlassView(entry: entry)
        }
        .configurationDisplayName("Train Rings")
        .description("Walk and train countdown rings, or a leave-by recommendation.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct PathHomeGlassView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BoardEntry
    var body: some View {
        ConfiguredBoard(entry: entry, family: family, rings: true)
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
        CommuteLiveActivity()
    }
}
