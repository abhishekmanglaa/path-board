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
}

/// What one moment of the board says, derived from a plan at `date`.
struct BoardSnapshot {
    struct Group {
        let destination: Destination
        let next: Departure?
        let minutesToNext: Int
        let minutesToLeave: Int
        /// Minutes to the next two trains after `next`.
        let following: [Int]

        var leaveText: String { minutesToLeave < 1 ? "Leave now" : "Leave in \(minutesToLeave) min" }
        var followingText: String? {
            following.isEmpty ? nil : "then " + following.map(String.init).joined(separator: ", ")
        }
    }

    let station: Station
    let walkMinutes: Int
    let groups: [Group]

    init(plan: Plan, at date: Date) {
        station = plan.station
        walkMinutes = plan.walkMinutes
        groups = plan.groups(at: date).map { dest, trains in
            Group(destination: dest,
                  next: trains.first,
                  minutesToNext: trains.first.map { Self.minutes(from: date, to: $0.date) } ?? 0,
                  minutesToLeave: trains.first.map { Self.minutes(from: date, to: plan.leaveBy($0)) } ?? 0,
                  following: trains.dropFirst().prefix(2).map { Self.minutes(from: date, to: $0.date) })
        }
    }

    /// Whole minutes remaining, rounded down like a departure board.
    static func minutes(from date: Date, to target: Date) -> Int { max(0, Int(target.timeIntervalSince(date) / 60)) }

    /// The soonest train across groups: what the one-number layouts show.
    var primary: Group? { groups.filter { $0.next != nil }.min { $0.minutesToNext < $1.minutesToNext } }
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
            MessageView(icon: "exclamationmark.triangle.fill", text: message, family: family)
        case .needsLocation:
            MessageView(icon: "location.slash.fill", text: "Open PATH Home to share your location", family: family)
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
    }
}

private struct SmallView: View {
    let snap: BoardSnapshot
    let stale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                WalkBadge(minutes: snap.walkMinutes, stale: stale)
                Text(snap.station.shortName)
                    .font(Theme.rounded(15, .heavy))
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            if snap.station.isHome {
                // Newport: one compact card per New York terminal.
                VStack(spacing: 5) {
                    ForEach(snap.groups, id: \.destination) { CompactCard(group: $0) }
                }
            } else if let group = snap.primary, let next = group.next {
                LineCard(line: next.line) {
                    VStack(alignment: .leading, spacing: 0) {
                        CardTitle(line: next.line)
                        Spacer(minLength: 2)
                        BigMinutes(minutes: group.minutesToNext, size: 38, ink: next.line.ink)
                        Text(group.leaveText).font(Theme.rounded(11, .heavy)).opacity(0.85)
                    }
                }
            } else {
                EmptyCard(note: snap.station.note)
            }
        }
    }
}

private struct MediumView: View {
    let snap: BoardSnapshot
    let stale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(snap.station.name).font(Theme.rounded(16, .heavy)).lineLimit(1)
                Spacer()
                WalkBadge(minutes: snap.walkMinutes, stale: stale)
            }
            if snap.station.isHome {
                HStack(spacing: 8) {
                    ForEach(snap.groups, id: \.destination) { TerminalCard(group: $0) }
                }
            } else if let group = snap.primary, let next = group.next {
                LineCard(line: next.line) {
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 0) {
                            CardTitle(line: next.line)
                            Spacer(minLength: 2)
                            Text(group.leaveText).font(Theme.rounded(13, .heavy))
                            if let note = snap.station.note {
                                Text(note).font(Theme.rounded(11, .semibold)).opacity(0.8)
                            }
                        }
                        Spacer(minLength: 4)
                        VStack(alignment: .trailing, spacing: 0) {
                            BigMinutes(minutes: group.minutesToNext, size: 46, ink: next.line.ink)
                            if let then = group.followingText {
                                Text(then).font(Theme.rounded(13, .heavy)).opacity(0.85)
                            }
                        }
                    }
                }
            } else {
                EmptyCard(note: snap.station.note)
            }
        }
    }
}

/// "8 min" with the live mark, Transit-style.
private struct BigMinutes: View {
    let minutes: Int
    let size: CGFloat
    let ink: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text("\(minutes)")
                .font(Theme.rounded(size, .black))
                .contentTransition(.numericText(countsDown: true))
            Text("min").font(Theme.rounded(size * 0.3, .heavy))
            RealtimeMark(color: ink)
                .frame(width: size * 0.3, height: size * 0.3)
                .padding(.leading, 2)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(minutes) minutes, live")
    }
}

private struct CardTitle: View {
    let line: PathLine

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(line.name)
                .font(Theme.rounded(13, .black))
                .lineLimit(1).minimumScaleFactor(0.7)
            HStack(spacing: 3) {
                Image(systemName: "arrow.right").font(Theme.rounded(10, .black))
                Text(line.towards).lineLimit(1).minimumScaleFactor(0.7)
            }
            .font(Theme.rounded(12, .bold))
            .opacity(0.85)
        }
    }
}

/// Newport small widget: one row per terminal.
private struct CompactCard: View {
    let group: BoardSnapshot.Group

    var body: some View {
        let line = group.next?.line
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(group.destination.short)
                .font(Theme.rounded(13, .black))
                .lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 2)
            if group.next != nil {
                Text("\(group.minutesToNext)")
                    .font(Theme.rounded(24, .black))
                    .contentTransition(.numericText(countsDown: true))
                Text("min").font(Theme.rounded(10, .heavy))
            } else {
                Text("—").font(Theme.rounded(20, .black))
            }
        }
        .foregroundStyle(line?.ink ?? .secondary)
        .padding(.horizontal, 9)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(line?.color ?? Color.secondary.opacity(0.2), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Newport medium widget: one card per terminal, side by side.
private struct TerminalCard: View {
    let group: BoardSnapshot.Group

    var body: some View {
        if let next = group.next {
            LineCard(line: next.line) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(next.line.name).font(Theme.rounded(12, .black)).lineLimit(1).minimumScaleFactor(0.7)
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.right").font(Theme.rounded(10, .black))
                        Text(group.destination.short).lineLimit(1)
                    }
                    .font(Theme.rounded(12, .bold)).opacity(0.85)
                    Spacer(minLength: 2)
                    BigMinutes(minutes: group.minutesToNext, size: 34, ink: next.line.ink)
                    Text(group.followingText ?? group.leaveText)
                        .font(Theme.rounded(11, .heavy)).opacity(0.85).lineLimit(1)
                }
            }
        } else {
            EmptyCard(note: "No train to \(group.destination.short)")
        }
    }
}

private struct LineCard<Content: View>: View {
    let line: PathLine
    @ViewBuilder let content: Content

    var body: some View {
        content
            .foregroundStyle(line.ink)
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background {
                ZStack(alignment: .leading) {
                    line.color
                    if let accent = line.accent { accent.frame(width: 5) }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct EmptyCard: View {
    let note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Spacer(minLength: 0)
            Text("No train listed").font(Theme.rounded(14, .heavy))
            if let note { Text(note).font(Theme.rounded(11, .semibold)).foregroundStyle(.secondary) }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct MessageView: View {
    let icon: String
    let text: String
    let family: WidgetFamily

    var body: some View {
        switch family {
        case .accessoryInline:
            Label(text, systemImage: icon)
        case .accessoryCircular:
            Image(systemName: icon).font(.title2)
        default:
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: icon).font(Theme.rounded(20, .heavy)).foregroundStyle(.orange)
                Spacer(minLength: 0)
                Text(text).font(Theme.rounded(13, .bold)).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Lock screen

private struct RectangularView: View {
    let snap: BoardSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("\(snap.walkMinutes) min · \(snap.station.shortName)", systemImage: "figure.walk")
                .font(Theme.rounded(13, .semibold))
                .lineLimit(1)
            if snap.station.isHome {
                ForEach(snap.groups, id: \.destination) { g in
                    Text(g.next == nil ? "\(g.destination.short) —" : "\(g.destination.short) \(g.minutesToNext) min")
                        .font(Theme.rounded(16, .heavy)).lineLimit(1)
                }
            } else if let g = snap.primary, let next = g.next {
                Text("\(next.line.name) \(g.minutesToNext) min")
                    .font(Theme.rounded(17, .heavy)).lineLimit(1).minimumScaleFactor(0.8)
                Text(g.leaveText).font(Theme.rounded(13, .semibold))
            } else {
                Text("No train listed").font(Theme.rounded(15, .heavy))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct InlineView: View {
    let snap: BoardSnapshot

    var body: some View {
        if snap.station.isHome {
            let parts = snap.groups.map { $0.next == nil ? "\($0.destination.short) –" : "\($0.destination.short) \($0.minutesToNext)" }
            Label(parts.joined(separator: " · "), systemImage: "tram.fill")
        } else if let g = snap.primary {
            // The inline slot fits ~20 characters; the station and countdown matter most.
            Label("\(g.minutesToNext) min · \(snap.station.shortName)", systemImage: "tram.fill")
        } else {
            Label("\(snap.station.shortName) · no train", systemImage: "tram.fill")
        }
    }
}

private struct CircularView: View {
    let snap: BoardSnapshot

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let g = snap.primary {
                VStack(spacing: -2) {
                    Text("\(g.minutesToNext)").font(Theme.rounded(22, .black))
                    Text(snap.station.isHome ? g.destination.short : "min")
                        .font(Theme.rounded(9, .heavy)).lineLimit(1).minimumScaleFactor(0.6)
                }
            } else {
                Image(systemName: "tram.fill").font(.title3)
            }
        }
    }
}
