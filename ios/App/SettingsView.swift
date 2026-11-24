import SwiftUI
import WidgetKit

struct SettingsView: View {
    @ObservedObject var monitor: LocationMonitor
    @Binding var buffer: Int
    @Binding var destinationIDs: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper("Station buffer: \(buffer) min", value: $buffer, in: 1...3)
                        .accessibilityIdentifier("stationBuffer")
                } header: { Text("Time to spare") } footer: {
                    Text("Added to your walking time before recommending a train. Estimates can change; give yourself extra time when needed.")
                }
                Section("At Newport, show") {
                    ForEach(Destination.newport) { destination in
                        Toggle(destination.label, isOn: Binding(
                            get: { destinationIDs.contains(destination.id) },
                            set: { enabled in
                                destinationIDs = Destination.newport.map(\.id).filter {
                                    $0 == destination.id ? enabled : destinationIDs.contains($0)
                                }
                            }))
                        .disabled(destinationIDs.count == 1 && destinationIDs.contains(destination.id))
                    }
                }
                Section {
                    Toggle("Follow me in the background", isOn: Binding(
                        get: { monitor.followsInBackground }, set: { monitor.setBackgroundFollowing($0) }))
                    if monitor.followsInBackground && !monitor.hasAlways {
                        Button("Enable Always Location") { monitor.requestAccess() }
                        Text("Choose Always in the app's location settings to let nearby-station widgets follow you while the app is closed.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if !monitor.hasAnyAccess {
                        Button("Add walking time with location") { monitor.requestAccess() }
                    }
                } header: { Text("Location") } footer: {
                    Text("Fixed stations work without location. Widgets use your last available location for automatic updates. Tap refresh for a new walking estimate. Background following can save a location when you move a significant distance.")
                }
                Section("Widgets") {
                    NavigationLink("Preview & set up widgets") { WidgetGallery(plan: monitor.plan ?? .sample(at: .now)) }
                    Text("Touch and hold a widget, then choose Edit Widget to set its station, directions, and display independently.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Understanding train times") {
                    Text("Live predictions are under two minutes old. Older predictions are labeled, and leave-by recommendations stop after five minutes or a failed refresh.")
                    Text("Timetable estimates fill in trains beyond the live feed. The app checks for new predictions every 30 seconds while open. iOS controls widget refresh timing.")
                }
                .font(.footnote)
            }
            .navigationTitle("Settings")
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}

struct WidgetGallery: View {
    let plan: Plan
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Add PATH Home from your Home Screen's widget gallery. Choose Train Home for departures or Train Rings for a visual countdown.")
                    .font(.callout).foregroundStyle(.secondary)
                Text("Train Home").font(.headline)
                BoardView(entry: BoardEntry(date: .now, state: .plan(plan)), family: .systemSmall)
                    .padding(16).frame(width: 170, height: 170)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
                BoardView(entry: BoardEntry(date: .now, state: .plan(plan)), family: .systemMedium)
                    .padding(16).frame(height: 170)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
                Text("Train Rings").font(.headline)
                GlassBoardView(entry: BoardEntry(date: .now, state: .plan(plan)), family: .systemSmall)
                    .padding(16).frame(width: 170, height: 170)
                    .background { GlassBackground().clipShape(RoundedRectangle(cornerRadius: 22)) }
                    .environment(\.colorScheme, .dark)
                Text("Live predictions show a broadcast mark. Older predictions and timetable estimates are labeled. Fixed widgets can show departures even without a location fix.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Widgets")
    }
}
