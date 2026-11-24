import SwiftUI
import WidgetKit

enum WidgetSnapshots {
    static func entry(options: WidgetOptions, cached: Plan?, isPreview: Bool, now: Date) -> BoardEntry {
        if isPreview {
            return BoardEntry(date: now, state: .plan(.sample(at: now, stationID: options.stationID ?? "NEW")), options: options)
        }
        if let cached, cached.selectionID == options.stationID,
           options.stationID == nil || cached.stationID == options.stationID {
            return BoardEntry(date: now, state: .plan(cached), options: options)
        }
        let state: BoardState = options.stationID == nil ? .needsLocation : .failed(message: "Refresh to load departures", stale: nil)
        return BoardEntry(date: now, state: state, options: options)
    }
}

struct WidgetTrustLabel: View {
    let freshness: PlanFreshness
    var offline = false
    var alerts: ServiceAlertPresentation? = nil
    private var text: String {
        if offline { return "Offline · earlier predictions" }
        switch freshness {
        case .fresh: return "Estimates shown faded"
        case .aging: return "Older predictions · refresh"
        case .expired: return "Expired prediction · refresh"
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let alerts, let alert = alerts.alerts.first {
                Label(alerts.isStale ? "Earlier alert · \(alert.scope)" : "\(alert.scope) alert",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            Text(text).foregroundStyle(.secondary)
        }
        .font(.system(size: 9, weight: .medium))
        .lineLimit(1).minimumScaleFactor(0.8)
    }
}

struct ServiceAlertGlyph: View {
    var color: Color = .orange

    var body: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(color)
            .accessibilityLabel("Service alert")
    }
}

struct ConfiguredBoard: View {
    let entry: BoardEntry
    let family: WidgetFamily
    var rings = false

    var body: some View {
        Group {
            if case .plan(let plan) = entry.state,
               entry.options.canRecommend(plan: plan, at: entry.date,
                 isAccessory: [.accessoryInline, .accessoryCircular, .accessoryRectangular].contains(family)) {
                RecommendationWidget(plan: plan, date: entry.date, family: family, options: entry.options)
            } else if rings {
                GlassBoardView(entry: entry, family: family, showing: entry.options.destinations)
            } else {
                BoardView(entry: entry, family: family, showing: entry.options.destinations)
            }
        }
        .environment(\.refreshStationID, entry.options.stationID ?? "")
    }
}

private struct RecommendationWidget: View {
    let plan: Plan
    let date: Date
    let family: WidgetFamily
    let options: WidgetOptions

    var body: some View {
        if let r = CommuteRecommendation.make(plan: plan, now: date, bufferMinutes: SharedStore.bufferMinutes,
                                               destinations: options.destinations) {
            switch family {
            case .accessoryInline:
                Text("\(r.departure.scheduled ? "Aim to leave" : "Leave") in \(r.leaveInMinutes(at: date))m · \(plan.station.shortName)")
            case .accessoryCircular:
                VStack(spacing: 0) {
                    Text("\(r.leaveInMinutes(at: date))").font(.title.bold()).widgetAccentable()
                    Text(r.departure.scheduled ? "aim / min" : "leave / min").font(.system(size: 9))
                }
            case .accessoryRectangular:
                VStack(alignment: .leading) {
                    Text(r.departure.scheduled ? "Aim to leave in \(r.leaveInMinutes(at: date))m" : "Leave in \(r.leaveInMinutes(at: date))m").font(.headline)
                    Text("\(plan.station.shortName) · \(r.walkMinutes)m walk").font(.caption)
                    Text(r.departure.headsign).font(.caption).lineLimit(1)
                }
            default:
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(plan.station.shortName).font(.caption.bold()).lineLimit(1)
                        Spacer(minLength: 0)
                        Button(intent: RefreshTrainsIntent(stationID: options.stationID ?? "")) {
                            Image(systemName: "arrow.clockwise").font(.caption).frame(width: 24, height: 24)
                        }.buttonStyle(.plain).accessibilityLabel("Refresh trains")
                    }
                    Text(r.departure.scheduled ? "Aim to leave" : "Leave in").font(.caption).foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("\(r.leaveInMinutes(at: date))").font(.system(size: 32, weight: .heavy, design: .rounded)).widgetAccentable()
                        Text("min").font(.caption.bold())
                    }
                    Text(r.departure.headsign).font(.caption.bold()).lineLimit(1).minimumScaleFactor(0.7)
                    Text("\(r.walkMinutes)m walk + \(r.bufferMinutes)m buffer").font(.system(size: 10)).foregroundStyle(.secondary)
                    WidgetTrustLabel(freshness: plan.freshness(at: date),
                        alerts: plan.serviceAlertPresentation(at: date, showing: options.destinations))
                }
            }
        } else {
            BoardView(entry: BoardEntry(date: date, state: .plan(plan), options: options), family: family, showing: options.destinations)
        }
    }
}
