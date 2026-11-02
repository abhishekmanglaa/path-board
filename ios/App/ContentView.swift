import SwiftUI
import WidgetKit

struct ContentView: View {
    @ObservedObject var monitor: LocationMonitor
    @State private var newportIDs = SharedStore.newportDestinationIDs

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !monitor.hasAlways { AccessBanner(monitor: monitor) }
                    if monitor.isFarAway {
                        Label(PlanError.farFromPATH.localizedDescription, systemImage: "map")
                            .font(Theme.rounded(20, .heavy))
                            .padding(.top, 40)
                    } else if let plan = monitor.plan {
                        // Redraw every second so minutes tick here the way they do on the widget.
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Departures(plan: plan, now: context.date, showing: newportDestinations)
                        }
                        WidgetGallery(plan: plan)
                    } else if monitor.hasAnyAccess {
                        ProgressView("Finding the nearest station…").frame(maxWidth: .infinity).padding(.top, 60)
                    }
                    if let error = monitor.error {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(Theme.rounded(14, .semibold)).foregroundStyle(.orange)
                    }
                    NewportSettings(ids: $newportIDs)
                }
                .padding(16)
            }
            .refreshable { monitor.refresh() }
            .onChange(of: newportIDs) { _, ids in
                SharedStore.newportDestinationIDs = ids
                WidgetCenter.shared.reloadAllTimelines()
            }
            .sensoryFeedback(.success, trigger: monitor.plan?.computedAt)
            .navigationTitle("Train Home")
            .toolbar {
                Button { monitor.refresh() } label: {
                    if monitor.isRefreshing { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                }
                .accessibilityLabel("Refresh")
            }
        }
    }
}

private struct AccessBanner: View {
    @ObservedObject var monitor: LocationMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(monitor.hasAnyAccess ? "Let the widget follow you" : "Find your nearest station",
                  systemImage: "location.fill")
                .font(Theme.rounded(17, .heavy))
            Text(monitor.hasAnyAccess
                 ? "Choose \"Always\" so the widget updates as you move between stations, even when this app is closed."
                 : "PATH Home uses your location to pick the closest station and time the walk there.")
                .font(Theme.rounded(14, .medium)).foregroundStyle(.secondary)
            Button(monitor.hasAnyAccess ? "Allow Always" : "Allow Location") { monitor.requestAccess() }
                .modernProminentButton()
                .tint(Theme.walk)
                .font(Theme.rounded(15, .heavy))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modernCard(cornerRadius: 20)
    }
}

private extension ContentView {
    var newportDestinations: [Destination] { Destination.newport.filter { newportIDs.contains($0.id) } }
}

/// Which directions the board lists at Newport. At least one stays on.
private struct NewportSettings: View {
    @Binding var ids: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AT NEWPORT, SHOW").font(Theme.rounded(12, .heavy)).foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ForEach(Destination.newport) { dest in
                    let on = ids.contains(dest.id)
                    Toggle(isOn: Binding(
                        get: { on },
                        set: { enable in
                            ids = Destination.newport.map(\.id).filter { $0 == dest.id ? enable : ids.contains($0) }
                        })) {
                        Label {
                            Text(dest.label).font(Theme.rounded(16, .bold))
                        } icon: {
                            Circle().fill(PathLine(feedColors: dest.lineColors, headsign: dest.headsign).color)
                                .frame(width: 12, height: 12)
                        }
                    }
                    .disabled(on && ids.count == 1)
                    .padding(.vertical, 8)
                    if dest.id != Destination.newport.last?.id { Divider() }
                }
            }
            .padding(.horizontal, 14)
            .modernCard(cornerRadius: 20)
            Text("The widget fits three on the small size and four on the medium.")
                .font(Theme.rounded(12, .medium)).foregroundStyle(.secondary)
        }
    }
}

/// Liquid Glass on iOS 26+, the closest pre-26 equivalent otherwise.
private extension View {
    @ViewBuilder func modernCard(cornerRadius: CGFloat) -> some View {
        if #available(iOS 26, *) {
            glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    @ViewBuilder func modernProminentButton() -> some View {
        if #available(iOS 26, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
        }
    }
}

private struct Departures: View {
    let plan: Plan
    let now: Date
    let showing: [Destination]

    var body: some View {
        let snap = BoardSnapshot(plan: plan, at: now, showing: showing)
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(plan.station.name).font(Theme.rounded(30, .black))
                Label("\(snap.walkMinutes) min walk", systemImage: "figure.walk")
                    .font(Theme.rounded(16, .heavy)).foregroundStyle(Theme.walk)
                if let note = plan.station.note {
                    Label(note, systemImage: "arrow.triangle.swap")
                        .font(Theme.rounded(16, .heavy)).foregroundStyle(.orange)
                }
            }
            if snap.rows.isEmpty {
                Text("No trains posted yet. PATH lists about two trains ahead per direction.")
                    .font(Theme.rounded(15, .semibold)).foregroundStyle(.secondary)
            }
            ForEach(snap.rows) { row in
                DirectionCard(row: row, home: plan.station.isHome)
            }
            Text("Updated \(plan.computedAt, style: .relative) ago")
                .font(Theme.rounded(12, .medium)).foregroundStyle(.tertiary)
        }
    }
}

/// One direction: the next train large, the ones after it with their clock times.
private struct DirectionCard: View {
    let row: BoardSnapshot.Row
    let home: Bool

    var body: some View {
        let line = row.line
        let next = row.next
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(home ? row.label : line.name).font(Theme.rounded(20, .black))
                    Text(home ? line.name : "→ \(line.towards)").font(Theme.rounded(14, .bold)).opacity(0.85)
                }
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    if !next.scheduled {
                        RealtimeMark(color: line.ink).frame(width: 14, height: 14).padding(.trailing, 2)
                    }
                    Text("\(next.minutes)").font(Theme.rounded(40, .black))
                        .contentTransition(.numericText(countsDown: true))
                    Text("min").font(Theme.rounded(14, .heavy))
                }
                .opacity(next.scheduled ? 0.8 : 1)
            }
            HStack(spacing: 14) {
                ForEach(row.trains, id: \.self) { t in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(t.departure.date.formatted(date: .omitted, time: .shortened))
                            .font(Theme.rounded(13, .heavy))
                        Text(t.scheduled ? "scheduled" : "live").font(Theme.rounded(11, .semibold)).opacity(0.75)
                    }
                    .opacity(t.scheduled ? 0.75 : 1)
                }
            }
        }
        .foregroundStyle(line.ink)
        .padding(14)
        .background {
            ZStack(alignment: .leading) {
                line.color
                if let accent = line.accent { accent.frame(width: 6) }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .animation(.default, value: next.minutes)
        .accessibilityElement(children: .combine)
    }
}

/// The real widget views at real widget sizes, fed the same plan the widget gets.
private struct WidgetGallery: View {
    let plan: Plan

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("WIDGET").font(Theme.rounded(12, .heavy)).foregroundStyle(.secondary)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let entry = BoardEntry(date: context.date, state: .plan(plan))
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        tile(entry, .systemSmall, 170, 170)
                        VStack(alignment: .leading, spacing: 10) {
                            lock(entry, .accessoryCircular, 72, 72)
                            lock(entry, .accessoryInline, 170, 22)
                        }
                    }
                    tile(entry, .systemMedium, 364, 170)
                    lock(entry, .accessoryRectangular, 172, 76)
                }
            }
        }
    }

    private func tile(_ entry: BoardEntry, _ family: WidgetFamily, _ w: CGFloat, _ h: CGFloat) -> some View {
        BoardView(entry: entry, family: family)
            .padding(14)
            .frame(width: w, height: h)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func lock(_ entry: BoardEntry, _ family: WidgetFamily, _ w: CGFloat, _ h: CGFloat) -> some View {
        BoardView(entry: entry, family: family)
            .frame(width: w, height: h)
            .padding(6)
            .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .foregroundStyle(.white)
            .environment(\.colorScheme, .dark)
    }
}
