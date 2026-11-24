import SwiftUI
import WidgetKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var monitor: LocationMonitor
    @ObservedObject private var activity = CommuteActivityController.shared
    @State private var showsStations = false
    @State private var showsSettings = false
    @State private var buffer = SharedStore.bufferMinutes
    @State private var destinationIDs = SharedStore.newportDestinationIDs
    @AppStorage("commute.heading", store: UserDefaults(suiteName: SharedStore.appGroup)) private var headingID = "33"

    private var shown: [Destination] { Destination.newport.filter { destinationIDs.contains($0.id) } }
    private var heading: [Destination] {
        let selected = shown.filter { $0.id == headingID }
        return selected.isEmpty ? Array(shown.prefix(1)) : selected
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Button { showsStations = true } label: {
                        HStack {
                            Image(systemName: monitor.selectedStationID == nil ? "location.fill" : "tram.fill")
                            VStack(alignment: .leading, spacing: 3) {
                                Text(monitor.plan?.station.name ?? monitor.selectedStationID.flatMap { Station.byID[$0]?.name } ?? "Find a station")
                                    .font(.title2.bold())
                                Text(monitor.selectedStationID == nil ? "Automatic · change station" : "Selected station · change")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.down").font(.caption.bold())
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("stationPicker")
                    if monitor.needsLocation {
                        ContentUnavailableView {
                            Label("Find your station", systemImage: "location")
                        } description: {
                            Text("Allow location to compare nearby stations and time the walk, or choose a station to browse departures.")
                        } actions: {
                            Button("Allow Location") { monitor.requestAccess() }.buttonStyle(.borderedProminent)
                            Button("Choose a station") { showsStations = true }
                        }
                    } else if monitor.isFarAway {
                        ContentUnavailableView("No PATH station nearby", systemImage: "map",
                            description: Text("Choose a station to check its departures from anywhere."))
                        Button("Choose a station") { showsStations = true }.buttonStyle(.bordered)
                    } else if let plan = monitor.plan {
                        if plan.station.isHome {
                            Picker("Heading to", selection: $headingID) {
                                ForEach(shown) { Text($0.short).tag($0.id) }
                            }
                            .pickerStyle(.segmented)
                            .accessibilityIdentifier("headingPicker")
                        }
                        if scenePhase == .active && !showsSettings && !showsStations {
                            TimelineView(DepartureTimelineSchedule(plan: plan,
                                bufferMinutes: buffer, destinations: shown)) { context in
                                dashboard(plan, at: context.date)
                            }
                        } else {
                            dashboard(plan, at: .now)
                        }
                        if !monitor.hasAnyAccess {
                            Button { monitor.requestAccess() } label: { Label("Add walking time with location", systemImage: "figure.walk") }
                                .font(.subheadline.weight(.semibold))
                        }
                    } else if monitor.isRefreshing {
                        ProgressView("Loading departures…").frame(maxWidth: .infinity).padding(.vertical, 60)
                    } else {
                        ContentUnavailableView("Departures unavailable", systemImage: "wifi.exclamationmark",
                            description: Text("Pull down to try again, or choose another station."))
                    }
                    if let error = monitor.error {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.callout).foregroundStyle(.orange)
                            .accessibilityIdentifier("refreshError")
                    }
                    if activity.isTracking {
                        Button(role: .destructive) { Task { await activity.end() } } label: {
                            Label("End Live Activity", systemImage: "stop.circle")
                        }
                        .accessibilityIdentifier("endActivity")
                    }
                }
                .padding(20)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .refreshable { await monitor.refresh() }
            .navigationTitle("Train Home")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { Task { await monitor.refresh() } } label: {
                        if monitor.isRefreshing { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                    }
                    .accessibilityLabel("Refresh departures")
                    .accessibilityIdentifier("refreshDepartures")
                    Button { showsSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings").accessibilityIdentifier("settings")
                }
            }
            .sheet(isPresented: $showsStations) { StationPicker(monitor: monitor) }
            .sheet(isPresented: $showsSettings) {
                SettingsView(monitor: monitor, buffer: $buffer, destinationIDs: $destinationIDs)
            }
            .onChange(of: buffer) { _, value in SharedStore.bufferMinutes = value; WidgetCenter.shared.reloadAllTimelines() }
            .onChange(of: destinationIDs) { _, ids in
                SharedStore.newportDestinationIDs = ids
                if !ids.contains(headingID), let first = ids.first { headingID = first }
                WidgetCenter.shared.reloadAllTimelines()
            }
            .alert("Live Activity", isPresented: Binding(get: { activity.error != nil }, set: { if !$0 { activity.error = nil } })) {
                Button("OK") { activity.error = nil }
            } message: { Text(activity.error ?? "") }
        }
        .tint(Theme.walk)
    }

    private func dashboard(_ plan: Plan, at date: Date) -> some View {
        CommuteDashboard(plan: plan, now: date, destinations: shown,
            recommendationDestinations: heading, buffer: buffer, offline: monitor.error != nil,
            track: { recommendation in Task { await activity.start(recommendation, plan: plan) } })
    }
}

private struct StationPicker: View {
    @ObservedObject var monitor: LocationMonitor
    @Environment(\.dismiss) private var dismiss
    @State private var pinned = SharedStore.pinnedStationIDs
    @State private var query = ""
    private var matches: [Station] {
        Station.all.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { choose(nil) } label: {
                        Label("Automatic · nearest useful station", systemImage: "location.fill")
                    }
                    Text("Walking routes are compared. Newport gets preference when walking home is practical.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if query.isEmpty && !monitor.nearbyStations.isEmpty {
                    Section("Nearby") { ForEach(monitor.nearbyStations, id: \.id) { row($0) } }
                }
                if query.isEmpty {
                    Section("Pinned") { ForEach(Station.all.filter { pinned.contains($0.id) }, id: \.id) { row($0) } }
                }
                Section("All stations") { ForEach(matches, id: \.id) { row($0) } }
            }
            .searchable(text: $query, prompt: "Find a station")
            .navigationTitle("Choose station")
            .toolbar { Button("Done") { dismiss() } }
        }
    }

    private func row(_ station: Station) -> some View {
        HStack {
            Button { choose(station.id) } label: {
                HStack {
                    Text(station.name).foregroundStyle(.primary)
                    Spacer()
                    if monitor.selectedStationID == station.id { Image(systemName: "checkmark").foregroundStyle(Theme.walk) }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("station-\(station.id)")
            Button {
                if pinned.contains(station.id) { pinned.removeAll { $0 == station.id } } else { pinned.append(station.id) }
                SharedStore.pinnedStationIDs = pinned
            } label: { Image(systemName: pinned.contains(station.id) ? "pin.fill" : "pin") }
                .buttonStyle(.borderless).padding(.leading, 8)
                .accessibilityLabel("\(pinned.contains(station.id) ? "Unpin" : "Pin") \(station.name)")
        }
        .padding(.vertical, 4)
    }

    private func choose(_ id: String?) {
        dismiss()
        Task { await monitor.selectStation(id) }
    }
}
