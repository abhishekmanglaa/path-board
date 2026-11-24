import SwiftUI

struct CommuteDashboard: View {
    let plan: Plan
    let now: Date
    var destinations = SharedStore.newportDestinations
    var recommendationDestinations = SharedStore.newportDestinations
    var buffer = 2
    var offline = false
    var track: (CommuteRecommendation) -> Void = { _ in }
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let recommendation = CommuteRecommendation.make(plan: plan, now: now, bufferMinutes: buffer,
            destinations: recommendationDestinations, offline: offline)
        let snapshot = BoardSnapshot(plan: plan, at: now, showing: destinations, offline: offline)
        VStack(alignment: .leading, spacing: 24) {
            if !snapshot.serviceAlerts.alerts.isEmpty {
                ServiceAlertsCard(presentation: snapshot.serviceAlerts)
            }
            VStack(alignment: .leading, spacing: 16) {
                Label(plan.freshnessText(at: now, offline: offline), systemImage: offline ? "wifi.slash" : "clock")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(plan.freshness(at: now) == .fresh && !offline ? Color.secondary : .orange)
                if let recommendation {
                    RecommendationSummary(recommendation: recommendation, now: now, station: plan.station,
                                          isAging: plan.freshness(at: now) == .aging)
                    Link(destination: plan.station.googleMapsWalkingURL) {
                        Group {
                            if typeSize.isAccessibilitySize { Text("Directions").font(.headline) }
                            else { Label("Directions", systemImage: "arrow.turn.up.right") }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    if plan.freshness(at: now) == .fresh {
                        Button { track(recommendation) } label: {
                            Label("Track on Lock Screen", systemImage: "lock.iphone")
                                .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity)
                        }
                        .accessibilityIdentifier("startActivity")
                        Text("Shows this prediction and countdown. Open the app for fresh train updates.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Text(adviceTitle).font(.largeTitle.bold()).fontDesign(.rounded)
                        .fixedSize(horizontal: false, vertical: true)
                    if snapshot.hasWalk {
                        Label("\(snapshot.walkLabel) walk to \(plan.station.shortName)", systemImage: "figure.walk")
                            .font(.headline)
                    }
                    Text(adviceDetail).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))

            VStack(alignment: .leading, spacing: 12) {
                Text("Departures").font(.title3.bold())
                if let note = plan.station.note {
                    Label(note, systemImage: "arrow.triangle.swap").font(.callout).foregroundStyle(.orange)
                }
                if snapshot.rows.isEmpty {
                    Text("No departures available for these directions. Try refreshing or choose another station.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                ForEach(snapshot.rows) { row in
                    DepartureCard(row: row, now: now, expired: snapshot.freshness == .expired, offline: offline)
                }
                Text("Faded times are timetable estimates. Train times can change.")
                    .font(.caption).foregroundStyle(.secondary)
                if snapshot.serviceAlerts.isUnavailable {
                    Text("Service alerts unavailable").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var adviceTitle: String {
        if offline { return "Check before leaving" }
        if plan.freshness(at: now) == .expired { return "Time for an update" }
        if !plan.hasReliableWalk(at: now) { return "Plan your next train" }
        return "Give yourself more time"
    }
    private var adviceDetail: String {
        if offline { return "These are earlier predictions. Refresh when you're connected for a leave-by recommendation." }
        if plan.freshness(at: now) == .expired { return "The prediction is over five minutes old. Refresh to check the trains before you head out." }
        if !plan.hasReliableWalk(at: now) { return "Browse departures below. A recent location near this station adds walking time and a leave-by recommendation." }
        return "None of the listed trains allows your walk and \(buffer)-minute station buffer. Check the following departures or refresh."
    }
}

private struct ServiceAlertsCard: View {
    let presentation: ServiceAlertPresentation

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(presentation.alerts) { alert in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(alert.title).font(.subheadline.weight(.semibold))
                        Text(alert.message).font(.callout)
                        Text(alert.publishedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                Link("View PATH alerts", destination: URL(string: "https://www.panynj.gov/path/en/alerts.html")!)
                    .font(.subheadline.weight(.semibold))
            }
            .padding(.top, 8)
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text(presentation.isStale ? "Earlier service alert" : "Service alert").font(.headline)
                    Text(Set(presentation.alerts.map(\.scope)).sorted().joined(separator: " · "))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
        }
        .padding(16)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityIdentifier("serviceAlerts")
    }
}

struct RecommendationSummary: View {
    let recommendation: CommuteRecommendation
    let now: Date
    let station: Station
    var isAging = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let minutes = recommendation.leaveInMinutes(at: now)
        VStack(alignment: .leading, spacing: 10) {
            Text(recommendation.departure.scheduled ? "AIM FOR THIS TRAIN" : isAging ? "CHECK BEFORE LEAVING" : "YOUR NEXT TRAIN")
                .font(.caption.bold()).tracking(1.3).foregroundStyle(.secondary)
            Text(minutes == 0 ? "Leave now" : "Leave in \(minutes) min")
                .font(.largeTitle.bold()).fontDesign(.rounded)
                .contentTransition(.numericText(countsDown: true))
                .accessibilityIdentifier("leaveAdvice")
            if typeSize.isAccessibilitySize {
                Label("\(recommendation.walkMinutes) min walk", systemImage: "figure.walk").font(.headline)
                Text("to \(station.name)").font(.body)
            } else {
                Label("\(recommendation.walkMinutes) min walk to \(station.shortName)", systemImage: "figure.walk").font(.headline)
            }
            Text("\(recommendation.departure.headsign) · \(recommendation.departure.date.formatted(date: .omitted, time: .shortened))")
                .font(.subheadline.weight(.medium))
            Text("Includes a \(recommendation.bufferMinutes)-minute station buffer")
                .font(.caption).foregroundStyle(.secondary)
            if recommendation.skippedTightTrain {
                Label("The earlier train is tight. This one gives you time.", systemImage: "figure.walk.motion")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if recommendation.departure.headsign.lowercased().hasPrefix("hoboken"),
               ["33S", "23S", "14S", "09S", "CHR"].contains(station.id) {
                Label("Change at Hoboken or walk onward to Newport", systemImage: "arrow.triangle.swap")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct DepartureCard: View {
    let row: BoardSnapshot.Row
    let now: Date
    let expired: Bool
    let offline: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            let header = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                                                     : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
            header {
                HStack(spacing: 8) {
                    Circle().fill(row.line.color).frame(width: 10, height: 10).accessibilityHidden(true)
                    Text(row.label).font(.headline)
                    if row.alertScope != nil { ServiceAlertGlyph() }
                }
                if !typeSize.isAccessibilitySize { Spacer(minLength: 4) }
                Text(row.next.departure.date, style: .time).font(.subheadline.monospacedDigit())
            }
            ViewThatFits(in: .horizontal) {
                departureTimes(horizontal: true)
                departureTimes(horizontal: false)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func departureTimes(horizontal: Bool) -> some View {
        let layout = horizontal ? AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 24))
                                : AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
        layout {
            ForEach(row.trains, id: \.self) { train in
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(train.minutes) min").font(.title2.bold()).fontDesign(.rounded).monospacedDigit()
                    Text(train.scheduled ? "Timetable estimate" : train.isLive && !offline ? "Live" : expired ? "Expired prediction" : "Earlier prediction")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .opacity(train.scheduled ? 0.65 : 1)
                .fixedSize(horizontal: horizontal, vertical: false)
            }
        }
    }
}
