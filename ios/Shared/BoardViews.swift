import SwiftUI
import WidgetKit

enum BoardState {
    case plan(Plan)
    case needsLocation
    /// Nowhere near PATH; there's no station to walk to.
    case farAway
    /// A refresh failed; show the last good plan if we have one.
    case failed(message: String, stale: Plan?)
}

struct BoardEntry: TimelineEntry {
    let date: Date
    let state: BoardState

    /// Smart Stack ranking: rises as the next train gets close to the walk time,
    /// so a stack rotates the train widget to the top when it actually matters.
    var relevance: TimelineEntryRelevance? {
        guard case .plan(let plan) = state, let next = BoardSnapshot(plan: plan, at: date).next else {
            return TimelineEntryRelevance(score: 0)
        }
        let slack = next.minutes - plan.walkMinutes
        let score: Float = slack <= 3 ? 1 : slack <= 12 ? 0.7 : 0.3
        return TimelineEntryRelevance(score: score, duration: 60)
    }
}

/// What one moment of the board says, derived from a plan at `date`: one row per
/// direction, each with its next few trains.
struct BoardSnapshot {
    struct Train: Hashable {
        let departure: Departure
        /// Whole minutes until it leaves, rounded up the way PATH's own signs and
        /// the RidePATH app count.
        let minutes: Int

        var scheduled: Bool { departure.scheduled }
    }

    struct Row: Hashable, Identifiable {
        let id: String
        /// The terminal at Newport, the line elsewhere.
        let label: String
        /// For the small widget's narrow rows.
        let tiny: String
        let trains: [Train]

        var line: PathLine { trains[0].departure.line }
        var next: Train { trains[0] }
    }

    static let trainsPerRow = 3

    let station: Station
    let walkMinutes: Int
    let rows: [Row]

    init(plan: Plan, at date: Date, showing destinations: [Destination] = SharedStore.newportDestinations) {
        station = plan.station
        walkMinutes = plan.walkMinutes
        let upcoming = plan.upcoming(at: date)
        func train(_ d: Departure) -> Train { Train(departure: d, minutes: Self.minutes(from: date, to: d.date)) }

        if plan.station.isHome {
            // Fixed order, like RidePATH, so each direction stays where the eye expects it.
            rows = destinations.compactMap { dest in
                let trains = upcoming.filter(dest.includes).prefix(Self.trainsPerRow).map(train)
                return trains.isEmpty ? nil : Row(id: dest.id, label: dest.short, tiny: dest.tiny, trains: trains)
            }
        } else {
            // One row per line that gets you to Newport, soonest line first.
            var lines: [String] = []
            for d in upcoming where !lines.contains(d.line.shortName) { lines.append(d.line.shortName) }
            rows = lines.map { name in
                Row(id: name, label: name, tiny: name,
                    trains: upcoming.filter { $0.line.shortName == name }.prefix(Self.trainsPerRow).map(train))
            }
        }
    }

    static func minutes(from date: Date, to target: Date) -> Int {
        max(0, Int((target.timeIntervalSince(date) / 60).rounded(.up)))
    }

    /// The soonest train in any row.
    var next: Train? { rows.map(\.next).min { $0.departure.date < $1.departure.date } }
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
    /// Which directions to list at Newport; the app's setting unless given.
    var showing: [Destination] = SharedStore.newportDestinations

    var body: some View {
        switch entry.state {
        case .plan(let plan):
            PlanView(snap: BoardSnapshot(plan: plan, at: entry.date, showing: showing), family: family, stale: false)
        case .failed(_, let stale?):
            PlanView(snap: BoardSnapshot(plan: stale, at: entry.date, showing: showing), family: family, stale: true)
        case .failed(let message, nil):
            MessageView(icon: "exclamationmark.triangle.fill", text: message, short: "Trains unavailable", family: family)
        case .needsLocation:
            MessageView(icon: "location.slash.fill", text: "Open PATH Home to share your location",
                        short: "Open app for location", family: family)
        case .farAway:
            MessageView(icon: "map", text: PlanError.farFromPATH.localizedDescription,
                        short: "No PATH nearby", family: family)
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

/// Shows as many directions as fit, tightening rows before dropping one — no
/// clipping on smaller widget sizes.
private struct TrainList<RowView: View>: View {
    let rows: [BoardSnapshot.Row]
    let spacing: CGFloat
    let height: CGFloat
    let row: (BoardSnapshot.Row, CGFloat) -> RowView

    var body: some View {
        if rows.isEmpty {
            EmptyCard()
        } else {
            // Each count at full height, then tightened, before giving up a direction.
            ViewThatFits(in: .vertical) {
                ForEach((1...min(rows.count, 4)).reversed(), id: \.self) { n in
                    list(n, height: height, spacing: spacing)
                    list(n, height: height * 0.78, spacing: spacing * 0.6)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private func list(_ count: Int, height: CGFloat, spacing: CGFloat) -> some View {
        VStack(spacing: spacing) {
            ForEach(rows.prefix(count)) { row($0, height) }
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
            TrainList(rows: snap.rows, spacing: 4, height: 24) { row, height in
                SmallRow(row: row, height: height)
            }
        }
    }
}

private struct SmallRow: View {
    @Environment(\.widgetRenderingMode) private var mode
    let row: BoardSnapshot.Row
    let height: CGFloat

    var body: some View {
        let paint = CardPaint(line: row.line, mode: mode)
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(row.tiny)
                .font(Theme.rounded(12, .black))
                .lineLimit(1).minimumScaleFactor(0.7)
                .layoutPriority(1)
            Spacer(minLength: 2)
            Times(trains: row.trains, size: 16, unit: false)
        }
        .foregroundStyle(paint.ink)
        .padding(.horizontal, 8)
        .frame(height: height)
        .background(RowBackground(paint: paint, accent: row.line.accent, cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Times.spoken(row))
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
            TrainList(rows: snap.rows, spacing: 5, height: 28) { row, height in
                MediumRow(row: row, home: snap.station.isHome, note: snap.station.note, height: height)
            }
        }
    }
}

private struct MediumRow: View {
    @Environment(\.widgetRenderingMode) private var mode
    let row: BoardSnapshot.Row
    let home: Bool
    /// "Change at Journal Sq" where no train runs straight to Newport.
    let note: String?
    let height: CGFloat

    var body: some View {
        let paint = CardPaint(line: row.line, mode: mode)
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(row.label)
                .font(Theme.rounded(13, .black))
                .lineLimit(1)
                .layoutPriority(2)
            // At Newport the row is the terminal, so name the line; elsewhere the
            // row is the line, so name where it's headed, or where to change.
            Group {
                if home {
                    Text(row.line.shortName)
                } else if let note {
                    Text(note)
                } else {
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.right").font(Theme.rounded(9, .black))
                        Text(row.line.towardsShort)
                    }
                }
            }
            .font(Theme.rounded(11, .bold))
            .opacity(0.8)
            .lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            Times(trains: row.trains, size: 18, unit: true)
                .layoutPriority(1)
            // Space is reserved on every row so the minute column lines up.
            RealtimeMark(color: paint.ink).frame(width: 9, height: 9)
                .opacity(row.next.scheduled ? 0 : 1)
                .accessibilityHidden(row.next.scheduled)
        }
        .foregroundStyle(paint.ink)
        .padding(.horizontal, 10)
        .frame(height: height)
        .background(RowBackground(paint: paint, accent: row.line.accent, cornerRadius: 9))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Times.spoken(row))
    }
}

/// "8 min  18  28": the next train large (the number the eye looks for, which
/// takes the accent tint), the ones after it smaller. Timetabled trains are
/// dimmed. Drops later trains rather than truncating when space runs out.
private struct Times: View {
    let trains: [BoardSnapshot.Train]
    let size: CGFloat
    /// Whether "min" follows the first count; the small widget has no room.
    let unit: Bool

    var body: some View {
        ViewThatFits(in: .horizontal) {
            ForEach((1...trains.count).reversed(), id: \.self) { n in
                HStack(alignment: .firstTextBaseline, spacing: size * 0.4) {
                    ForEach(Array(trains.prefix(n).enumerated()), id: \.element) { i, t in
                        count(t, first: i == 0)
                    }
                }
            }
        }
        .lineLimit(1)
    }

    @ViewBuilder private func count(_ t: BoardSnapshot.Train, first: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text("\(t.minutes)")
                .font(Theme.rounded(first ? size : size * 0.72, first ? .black : .heavy))
                .contentTransition(.numericText(countsDown: true))
                .widgetAccentable(first)
                .invalidatableContent()
            if first && unit { Text("min").font(Theme.rounded(size * 0.55, .heavy)) }
        }
        .opacity(t.scheduled ? (first ? 0.8 : 0.6) : (first ? 1 : 0.85))
        .fixedSize()
    }

    static func spoken(_ row: BoardSnapshot.Row) -> String {
        let times = row.trains.map { "\($0.minutes)\($0.scheduled ? " scheduled" : "")" }
        return "\(row.label) in \(times.joined(separator: ", ")) minutes"
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

extension BoardSnapshot.Row {
    /// "3 · 13 · 23" for the first `count` trains.
    func list(_ count: Int) -> String {
        trains.prefix(count).map { "\($0.minutes)" }.joined(separator: " · ")
    }
}

private struct RectangularView: View {
    let snap: BoardSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Label("\(snap.walkMinutes) min · \(snap.station.shortName)", systemImage: "figure.walk")
                .font(Theme.rounded(13, .semibold))
                .lineLimit(1).minimumScaleFactor(0.8)
            if snap.rows.isEmpty {
                Text("No trains posted yet").font(Theme.rounded(15, .heavy))
            }
            ForEach(snap.rows.prefix(2)) { row in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(row.tiny).font(Theme.rounded(13, .bold))
                    // As many departures as fit on the line.
                    ViewThatFits(in: .horizontal) {
                        ForEach((1...row.trains.count).reversed(), id: \.self) { n in
                            Text(row.list(n) + " min")
                        }
                    }
                    .font(Theme.rounded(17, .heavy))
                    .widgetAccentable()
                }
                .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct InlineView: View {
    let snap: BoardSnapshot

    var body: some View {
        // The inline slot fits ~20 characters: as many directions' next train as fit.
        if snap.rows.isEmpty {
            Label("\(snap.station.shortName) · no trains", systemImage: "tram.fill")
        } else {
            ViewThatFits(in: .horizontal) {
                ForEach((1...snap.rows.count).reversed(), id: \.self) { n in
                    Label(snap.rows.prefix(n).map { "\($0.tiny) \($0.next.minutes)" }.joined(separator: " · ") + " min",
                          systemImage: "tram.fill")
                }
            }
        }
    }
}

private struct CircularView: View {
    let snap: BoardSnapshot

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let row = snap.rows.min(by: { $0.next.departure.date < $1.next.departure.date }) {
                VStack(spacing: -2) {
                    Text("\(row.next.minutes)").font(Theme.rounded(22, .black)).widgetAccentable()
                    Text(snap.station.isHome ? row.tiny : "min")
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
