import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct CommuteLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CommuteActivity.self) { context in
            VStack(alignment: .leading, spacing: 0) {
                CommuteActivityCard(state: context.state, stationName: context.attributes.stationName, isStale: context.isStale)
                Button(intent: EndCommuteIntent()) { Label("End tracking", systemImage: "stop.circle") }
                    .font(.caption).padding(.horizontal, 14).padding(.bottom, 8)
            }
            .activityBackgroundTint(Color(uiColor: .secondarySystemBackground))
            .activitySystemActionForegroundColor(.primary)
            .widgetURL(URL(string: "pathhome://open"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.stationName, systemImage: "tram.fill").font(.caption.bold())
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.departureAt, style: .time).font(.caption.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.isStale ? "Open app to check train" : context.state.scheduled ? "Aim to leave" : "Leave by")
                            .font(.caption).foregroundStyle(context.isStale ? .orange : .secondary)
                        if !context.isStale { Text(context.state.leaveAt, style: .time).font(.title2.bold()) }
                        Text(context.state.headsign).font(.caption).lineLimit(1)
                    }
                }
            } compactLeading: {
                Image(systemName: context.isStale ? "arrow.clockwise" : "tram.fill")
            } compactTrailing: {
                if context.isStale { Text("Check").font(.caption) }
                else {
                    Text(timerInterval: min(Date(), context.state.leaveAt)...max(Date(), context.state.leaveAt), countsDown: true)
                        .monospacedDigit().frame(maxWidth: 50)
                }
            } minimal: {
                Image(systemName: context.isStale ? "arrow.clockwise" : "tram.fill")
            }
            .widgetURL(URL(string: "pathhome://open"))
            .keylineTint(Theme.walk)
        }
    }
}

