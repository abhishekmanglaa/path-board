import SwiftUI
import WidgetKit

/// The "Train Rings" widget: the board as rings on glass, like the Batteries
/// widget. One ring per direction drains as its next train gets closer; the walk
/// gets its own ring, so "can I make it" is a glance at two ring lengths.
struct GlassBoardView: View {
    let entry: BoardEntry
    let family: WidgetFamily

    var body: some View {
        switch entry.state {
        case .plan(let plan):
            GlassPlanView(snap: BoardSnapshot(plan: plan, at: entry.date), family: family, stale: false)
        case .failed(_, let stale?):
            GlassPlanView(snap: BoardSnapshot(plan: stale, at: entry.date), family: family, stale: true)
        case .failed:
            GlassMessage(icon: "exclamationmark.triangle.fill", text: "Trains unavailable")
        case .needsLocation:
            GlassMessage(icon: "location.slash.fill", text: "Open PATH Home to share your location")
        }
    }
}

/// Dark smoked glass with a lit top edge. In iOS's Clear and Tinted home screen
/// styles the system swaps this for real Liquid Glass.
struct GlassBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.20), Color(white: 0.08)], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [.white.opacity(0.10), .clear], center: .topLeading, startRadius: 0, endRadius: 220)
        }
    }
}

/// What each ring shows.
struct RingCell: Hashable, Identifiable {
    enum Kind: Hashable { case walk, train(scheduled: Bool) }

    let id: String
    let kind: Kind
    let minutes: Int
    let label: String
    /// Trains after this one, for the medium size.
    let after: [Int]
    let color: Color

    /// Rings span this many minutes: full at 20+, empty as the train arrives.
    static let span = 20.0
    var fraction: Double { min(1, max(0.04, Double(minutes) / Self.span)) }

    /// Walk first, then each direction's next train. With `fill`, gaps take the
    /// first direction's later trains, so a station with one line still shows
    /// three times (the medium size lists later trains under each ring instead).
    static func cells(_ snap: BoardSnapshot, count: Int, fill: Bool) -> [RingCell] {
        var cells = [RingCell(id: "walk", kind: .walk, minutes: snap.walkMinutes, label: "walk",
                              after: [], color: Theme.walk)]
        for row in snap.rows {
            cells.append(RingCell(id: row.id, kind: .train(scheduled: row.next.scheduled), minutes: row.next.minutes,
                                  label: row.tiny, after: row.trains.dropFirst().map(\.minutes), color: row.line.color))
        }
        if fill, let first = snap.rows.first {
            // Later trains get rings of their own, so don't also list them underneath.
            cells = cells.map { RingCell(id: $0.id, kind: $0.kind, minutes: $0.minutes, label: $0.label, after: [], color: $0.color) }
            for (i, t) in first.trains.dropFirst().enumerated() where cells.count < count {
                cells.append(RingCell(id: "\(first.id)+\(i)", kind: .train(scheduled: t.scheduled), minutes: t.minutes,
                                      label: "then", after: [], color: first.line.color))
            }
        }
        return Array(cells.prefix(count))
    }
}

private struct GlassPlanView: View {
    let snap: BoardSnapshot
    let family: WidgetFamily
    let stale: Bool

    var body: some View {
        switch family {
        case .systemMedium: medium
        default: small
        }
    }

    private var small: some View {
        let cells = RingCell.cells(snap, count: 4, fill: true)
        return Group {
            if cells.count == 1 {
                VStack(spacing: 8) {
                    Ring(cell: cells[0])
                    Text("No trains posted").font(Theme.rounded(12, .heavy)).foregroundStyle(.secondary)
                }
            } else if cells.count == 2 {
                HStack(spacing: 10) { Ring(cell: cells[0]); Ring(cell: cells[1]) }
                    .frame(maxHeight: .infinity)
            } else {
                Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                    GridRow { cell(cells, 0); cell(cells, 1) }
                    GridRow { cell(cells, 2); cell(cells, 3) }
                }
            }
        }
        .overlay(alignment: .topTrailing) { if stale { StaleDot() } }
    }

    @ViewBuilder private func cell(_ cells: [RingCell], _ i: Int) -> some View {
        if i < cells.count { Ring(cell: cells[i]) } else { Color.clear }
    }

    private var medium: some View {
        // With one or two lines there's room for later trains as rings of their own.
        let cells = RingCell.cells(snap, count: snap.rows.count < 3 ? 4 : 5, fill: snap.rows.count < 3)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(snap.station.name).font(Theme.rounded(15, .heavy)).lineLimit(1).minimumScaleFactor(0.8)
                if stale { StaleDot() }
                Spacer(minLength: 4)
                GlassRefreshButton()
            }
            if cells.count == 1 {
                HStack(spacing: 12) {
                    Ring(cell: cells[0]).frame(width: 70)
                    Text("No trains posted yet").font(Theme.rounded(14, .heavy)).foregroundStyle(.secondary)
                }
                .frame(maxHeight: .infinity)
            } else {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(cells) { c in
                        VStack(spacing: 4) {
                            Ring(cell: c)
                            Text(c.after.isEmpty ? " " : c.after.map(String.init).joined(separator: " · "))
                                .font(Theme.rounded(11, .heavy))
                                .foregroundStyle(.secondary)
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
    }
}

/// A Batteries-style ring: grey track, colored arc from 12 o'clock, the count and
/// label in the middle.
private struct Ring: View {
    @Environment(\.widgetRenderingMode) private var mode
    let cell: RingCell

    var body: some View {
        GeometryReader { geo in
            let d = min(geo.size.width, geo.size.height)
            let line = max(4, d * 0.11)
            ZStack {
                // Inset by half the stroke so the ring stays inside its cell.
                Group {
                    Circle().stroke(.white.opacity(0.14), lineWidth: line)
                    Circle()
                        .trim(from: 0, to: cell.fraction)
                        .stroke(mode == .fullColor ? cell.color : .white,
                                style: StrokeStyle(lineWidth: line, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .opacity(scheduled ? 0.6 : 1)
                        .widgetAccentable()
                }
                .padding(line / 2)
                VStack(spacing: -d * 0.03) {
                    if case .walk = cell.kind {
                        Image(systemName: "figure.walk").font(.system(size: d * 0.2, weight: .heavy))
                    }
                    Text("\(cell.minutes)")
                        .font(Theme.rounded(d * (cell.kind == .walk ? 0.26 : 0.34), .black))
                        .contentTransition(.numericText(countsDown: true))
                        .invalidatableContent()
                    if cell.kind != .walk {
                        Text(cell.label).font(Theme.rounded(d * 0.15, .heavy)).opacity(0.75)
                    }
                }
                .lineLimit(1).minimumScaleFactor(0.6)
                .padding(line * 1.6)
                .foregroundStyle(.white)
            }
            .frame(width: d, height: d)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(cell.kind == .walk ? "\(cell.minutes) minute walk"
                            : "\(cell.label) in \(cell.minutes) minutes\(scheduled ? ", scheduled" : "")")
    }

    private var scheduled: Bool { cell.kind == .train(scheduled: true) }
}

private struct StaleDot: View {
    var body: some View {
        Image(systemName: "exclamationmark.circle.fill").font(Theme.rounded(12)).foregroundStyle(.orange)
            .accessibilityLabel("Not updated recently")
    }
}

private struct GlassRefreshButton: View {
    var body: some View {
        Button(intent: RefreshTrainsIntent()) {
            Image(systemName: "arrow.clockwise")
                .font(Theme.rounded(11, .heavy))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 24, height: 24)
                .background(.white.opacity(0.14), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Refresh trains")
    }
}

private struct GlassMessage: View {
    let icon: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).font(Theme.rounded(20, .heavy)).foregroundStyle(.orange)
            Spacer(minLength: 0)
            Text(text).font(Theme.rounded(13, .bold)).foregroundStyle(.white).lineLimit(4).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
