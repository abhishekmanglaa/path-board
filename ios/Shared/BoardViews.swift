import SwiftUI
import WidgetKit

enum BoardState {
    case plan(Plan)
    case needsLocation
    /// A refresh failed; show the last good plan if we have one.
    case failed(message: String, stale: Plan?)
}

struct BoardEntry: TimelineEntry {
    let date: Date
    let state: BoardState

    /// Smart Stack ranking: rises as the next train gets close to the walk time,
    /// so a stack rotates the train widget to the top when it actually matters.
    var relevance: TimelineEntryRelevance? {
        guard case .plan(let plan) = state, let next = BoardSnapshot(plan: plan, at: date).rows.first else {
            return TimelineEntryRelevance(score: 0)
        }
        let slack = next.minutes - plan.walkMinutes
        let score: Float = slack <= 3 ? 1 : slack <= 12 ? 0.7 : 0.3
        return TimelineEntryRelevance(score: score, duration: 60)
    }
}

/// What one moment of the board says, derived from a plan at `date`.
struct BoardSnapshot {
    struct Row: Hashable {
        let departure: Departure
        /// Whole minutes until it leaves, rounded down like a departure board.
        let minutes: Int
        /// What the row is called: the line away from home, the terminal at Newport.
        let label: String

        var line: PathLine { departure.line }
    }

    let station: Station
    let walkMinutes: Int
    /// Up to three trains, in display order; layouts show as many as fit.
    let rows: [Row]

    init(plan: Plan, at date: Date) {
        station = plan.station
        walkMinutes = plan.walkMinutes
        let home = plan.station.isHome
        rows = plan.rows(at: date).prefix(3).map { d in
            Row(departure: d,
                minutes: Self.minutes(from: date, to: d.date),
                label: home ? Self.terminal(for: d, at: plan.station) : d.line.shortName)
        }
    }

    static func minutes(from date: Date, to target: Date) -> Int { max(0, Int(target.timeIntervalSince(date) / 60)) }

    private static func terminal(for d: Departure, at station: Station) -> String {
        station.destinations.first { $0.includes(d) }?.short ?? d.line.shortName
    }

    /// "4 · 14 · 24" for the first `count` trains.
    func minutesList(_ count: Int) -> String {
        rows.prefix(count).map { "\($0.minutes)" }.joined(separator: " · ")
    }

    /// At Newport, minutes per terminal in order ("WTC" → [6, 16]), so one-line
    /// layouts never put a 33rd St time under a WTC label.
    var terminals: [(label: String, minutes: [Int])] {
        var out: [(label: String, minutes: [Int])] = []
        for r in rows {
            if let i = out.firstIndex(where: { $0.label == r.label }) { out[i].minutes.append(r.minutes) }
            else { out.append((r.label, [r.minutes])) }
        }
        return out
    }
}

extension Station {
    var shortName: String {
        switch id {
        case "WTC": return "WTC"
        case "EXP": return "Exchange Pl"
        case "JSQ": return "Journal Sq"
        default: return name.replacingOccurrences(of: "Street", with: "St")
        }
    }
}

// MARK: - Board

struct BoardView: View {
    let entry: BoardEntry
    let family: WidgetFamily

    var body: some View {
        switch entry.state {
        case .plan(let plan):
            PlanView(snap: BoardSnapshot(plan: plan, at: entry.date), family: family, stale: false)
        case .failed(_, let stale?):
            PlanView(snap: BoardSnapshot(plan: stale, at: entry.date), family: family, stale: true)
        case .failed(let message, nil):
            MessageView(icon: "exclamationmark.triangle.fill", text: message, short: "Trains unavailable", family: family)
        case .needsLocation:
            MessageView(icon: "location.slash.fill", text: "Open PATH Home to share your location",
                        short: "Open app for location", family: family)
        }
    }
}

private struct PlanView: View {
    let snap: BoardSnapshot
    let family: WidgetFamily
    let stale: Bool

    var body: some View {
        switch family {
        case .accessoryInline: InlineView(snap: snap)
        case .accessoryCircular: CircularView(snap: snap)
        case .accessoryRectangular: RectangularView(snap: snap)
        case .systemMedium: MediumView(snap: snap, stale: stale)
        default: SmallView(snap: snap, stale: stale)
        }
    }
}

// MARK: - Home screen

private struct WalkBadge: View {
    let minutes: Int
    let stale: Bool

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "figure.walk").font(Theme.rounded(12, .heavy))
            Text("\(minutes) min").font(Theme.rounded(13, .heavy))
            if stale {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(Theme.rounded(11)).foregroundStyle(.orange)
                    .accessibilityLabel("Not updated recently")
            }
        }
        .foregroundStyle(Theme.walk)
        .lineLimit(1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(minutes) minute walk")
    }
}

/// Shows as many rows as fit (3, else 2, else 1), so a third train appears only
/// where there's room for it — no clipping on smaller widget sizes.
private struct TrainList<RowView: View>: View {
    let rows: [BoardSnapshot.Row]
    let spacing: CGFloat
    let row: (BoardSnapshot.Row, Bool) -> RowView

    var body: some View {
        if rows.isEmpty {
            EmptyCard()
        } else {
            ViewThatFits(in: .vertical) {
                ForEach([3, 2, 1].filter { $0 <= rows.count }, id: \.self) { count in
                    VStack(spacing: spacing) {
                        ForEach(Array(rows.prefix(count).enumerated()), id: \.element) { i, r in
                            row(r, i == 0)
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }
}

private struct SmallView: View {
    let snap: BoardSnapshot
    let stale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 4) {
                VStack(alignment: .leading, spacing: 0) {
                    WalkBadge(minutes: snap.walkMinutes, stale: stale)
                    Text(snap.station.shortName)
                        .font(Theme.rounded(15, .heavy))
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
                RefreshButton()
            }
            TrainList(rows: snap.rows, spacing: 4) { row, _ in
                SmallRow(row: row)
            }
        }
    }
}

private struct SmallRow: View {
    @Environment(\.widgetRenderingMode) private var mode
    let row: BoardSnapshot.Row

    var body: some View {
        let paint = CardPaint(line: row.line, mode: mode)
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(row.label)
                .font(Theme.rounded(12, .black))
                .lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 2)
            Minutes(value: row.minutes, size: 17)
        }
        .foregroundStyle(paint.ink)
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(RowBackground(paint: paint, accent: row.line.accent, cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.label) in \(row.minutes) minutes")
    }
}

private struct MediumView: View {
    let snap: BoardSnapshot
    let stale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text(snap.station.name)
                    .font(Theme.rounded(16, .heavy))
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                WalkBadge(minutes: snap.walkMinutes, stale: stale)
                RefreshButton()
            }
            TrainList(rows: snap.rows, spacing: 5) { row, first in
                MediumRow(row: row, live: first)
            }
        }
    }
}

private struct MediumRow: View {
    @Environment(\.widgetRenderingMode) private var mode
    let row: BoardSnapshot.Row
    let live: Bool

    var body: some View {
        let paint = CardPaint(line: row.line, mode: mode)
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(row.line.shortName)
                .font(Theme.rounded(13, .black))
                .lineLimit(1)
                .layoutPriority(1)
            HStack(spacing: 2) {
                Image(systemName: "arrow.right").font(Theme.rounded(9, .black))
                Text(row.line.towardsShort)
            }
            .font(Theme.rounded(12, .bold))
            .opacity(0.85)
            .lineLimit(1).minimumScaleFactor(0.75)
            Spacer(minLength: 4)
            Text(row.departure.date, style: .time)
                .font(Theme.rounded(11, .semibold))
                .opacity(0.8)
                .lineLimit(1)
                .fixedSize()
            Minutes(value: row.minutes, size: 18)
                .frame(minWidth: 52, alignment: .trailing)
            // Space is reserved on every row so the minute column lines up.
            RealtimeMark(color: paint.ink).frame(width: 9, height: 9)
                .opacity(live ? 1 : 0)
                .accessibilityHidden(!live)
        }
        .foregroundStyle(paint.ink)
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(RowBackground(paint: paint, accent: row.line.accent, cornerRadius: 9))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.line.name) to \(row.line.towards) in \(row.minutes) minutes")
    }
}

/// "8 min": the count is what the eye looks for; it takes the accent tint and
/// shimmers while a refresh is in flight.
private struct Minutes: View {
    let value: Int
    let size: CGFloat

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text("\(value)")
                .font(Theme.rounded(size, .black))
                .contentTransition(.numericText(countsDown: true))
                .widgetAccentable()
                .invalidatableContent()
            Text("min").font(Theme.rounded(size * 0.55, .heavy))
        }
        .lineLimit(1)
        .fixedSize()
    }
}

/// Row colors for the current rendering mode. In full color it's the line's own
/// fill and ink. In tinted (accented) and lock screen (vibrant) modes iOS paints
/// everything in one tint, so a solid fill would swallow its own text: use a
/// translucent plate with light text instead.
private struct CardPaint {
    let fill: Color
    let ink: Color
    let isFullColor: Bool

    init(line: PathLine, mode: WidgetRenderingMode) {
        isFullColor = mode == .fullColor
        fill = isFullColor ? line.color : Color.white.opacity(0.16)
        ink = isFullColor ? line.ink : .white
    }

}

/// A row's fill, with a fixed-width stripe in the second color for combined
/// overnight lines (full color only). Fixed width so it never reaches the text,
/// however wide the row is.
private struct RowBackground: View {
    let paint: CardPaint
    let accent: Color?
    let cornerRadius: CGFloat

    var body: some View {
        ZStack(alignment: .leading) {
            paint.fill
            if paint.isFullColor, let accent { accent.frame(width: 4) }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Refetches trains in place (iOS 17 interactive widgets) without opening the app.
private struct RefreshButton: View {
    var body: some View {
        Button(intent: RefreshTrainsIntent()) {
            Image(systemName: "arrow.clockwise")
                .font(Theme.rounded(11, .heavy))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background(.quaternary, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Refresh trains")
    }
}

/// PATH only posts about two trains per direction; between postings there can
/// be nothing to list.
private struct EmptyCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Spacer(minLength: 0)
            Text("No trains posted yet").font(Theme.rounded(13, .heavy))
                .lineLimit(2).minimumScaleFactor(0.8)
            Text("Tap ↻ to check again").font(Theme.rounded(11, .semibold)).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct MessageView: View {
    let icon: String
    let text: String
    /// For the inline lock screen slot, which fits ~20 characters.
    let short: String
    let family: WidgetFamily

    var body: some View {
        switch family {
        case .accessoryInline:
            Label(short, systemImage: icon)
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: icon).font(.title3)
            }
        case .accessoryRectangular:
            Label(text, systemImage: icon)
                .font(Theme.rounded(13, .semibold))
                .lineLimit(3).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
        default:
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: icon).font(Theme.rounded(20, .heavy)).foregroundStyle(.orange)
                Spacer(minLength: 0)
                Text(text).font(Theme.rounded(13, .bold))
                    .lineLimit(4).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Lock screen

private struct RectangularView: View {
    let snap: BoardSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Label("\(snap.walkMinutes) min · \(snap.station.shortName)", systemImage: "figure.walk")
                .font(Theme.rounded(13, .semibold))
                .lineLimit(1).minimumScaleFactor(0.8)
            if snap.station.isHome, !snap.rows.isEmpty {
                ForEach(snap.terminals.prefix(2), id: \.label) { t in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(t.label).font(Theme.rounded(13, .bold))
                        Text(t.minutes.prefix(2).map(String.init).joined(separator: " · ") + " min")
                            .font(Theme.rounded(17, .heavy))
                            .widgetAccentable()
                    }
                    .lineLimit(1).minimumScaleFactor(0.8)
                }
            } else if let first = snap.rows.first {
                Text(first.label)
                    .font(Theme.rounded(13, .bold))
                    .lineLimit(1)
                // As many departures as fit on one line.
                ViewThatFits(in: .horizontal) {
                    ForEach([3, 2, 1].filter { $0 <= snap.rows.count }, id: \.self) { n in
                        Text(snap.minutesList(n) + " min")
                    }
                }
                .font(Theme.rounded(18, .heavy))
                .widgetAccentable()
            } else {
                Text("No trains posted yet").font(Theme.rounded(15, .heavy))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct InlineView: View {
    let snap: BoardSnapshot

    var body: some View {
        // The inline slot fits ~20 characters; station and the next two counts.
        if snap.rows.isEmpty {
            Label("\(snap.station.shortName) · no trains", systemImage: "tram.fill")
        } else if snap.station.isHome {
            Label(snap.terminals.map { "\($0.label) \($0.minutes[0])" }.joined(separator: " · ") + " min",
                  systemImage: "tram.fill")
        } else {
            ViewThatFits(in: .horizontal) {
                Label("\(snap.station.shortName) \(snap.minutesList(2)) min", systemImage: "tram.fill")
                Label("\(snap.station.shortName) \(snap.minutesList(1)) min", systemImage: "tram.fill")
            }
        }
    }
}

private struct CircularView: View {
    let snap: BoardSnapshot

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let first = snap.rows.first {
                VStack(spacing: -2) {
                    Text("\(first.minutes)").font(Theme.rounded(22, .black)).widgetAccentable()
                    Text(snap.station.isHome ? first.label : "min")
                        .font(Theme.rounded(10, .bold))
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
                .padding(.horizontal, 4)
            } else {
                Image(systemName: "tram.fill").font(.title3)
            }
        }
    }
}
