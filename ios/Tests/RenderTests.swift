import SwiftUI
import WidgetKit
import XCTest
@testable import PathHome

/// Renders every widget family at real sizes, in light, dark and tinted modes,
/// into contact sheets for visual review. Runs only when RENDER_DIR is set
/// (pass TEST_RUNNER_RENDER_DIR=/some/dir to xcodebuild).
@MainActor
final class RenderTests: XCTestCase {
    enum Mode: String, CaseIterable { case light, dark, tinted }

    /// Home screen sizes in points: smallest supported (SE), iPhone 13 Pro, largest (Pro Max).
    static let small: [CGFloat] = [148, 158, 170]
    static let medium: [CGSize] = [CGSize(width: 321, height: 148), CGSize(width: 338, height: 158), CGSize(width: 364, height: 170)]

    /// Monday 8:30 AM in New York, when Newport's timetable is dense.
    let now = Date(timeIntervalSince1970: 1_793_626_200)

    private func scenarios() -> [(String, BoardState)] {
        let wtc = { (m: Double) in Departure(date: self.now.addingTimeInterval(m * 60 + 30), headsign: "World Trade Center", lineColors: "65C100") }
        let s33 = { (m: Double) in Departure(date: self.now.addingTimeInterval(m * 60 + 30), headsign: "33rd Street", lineColors: "FF9900") }
        func plan(_ id: String, walk: Double, _ deps: [Departure]) -> Plan {
            let st = Station.byID[id]!
            return Plan(stationID: id, walkSeconds: walk * 60, departures: deps, computedAt: now,
                        originLatitude: st.latitude, originLongitude: st.longitude)
        }
        return [
            ("away-three", .plan(.sample(at: now, stationID: "33S", walkMinutes: 4, minutes: [4, 14, 104]))),
            ("away-viahob", .plan(.sample(at: now, stationID: "33S", walkMinutes: 2, minutes: [5, 25],
                                          colors: "4D92FB,FF9900", headsign: "Journal Square via Hoboken"))),
            ("away-one", .plan(.sample(at: now, stationID: "CHR", walkMinutes: 12, minutes: [9]))),
            ("away-wtc", .plan(.sample(at: now, stationID: "WTC", walkMinutes: 6, minutes: [3, 13, 23],
                                       colors: "65C100", headsign: "Hoboken"))),
            ("home", .plan(plan("NEW", walk: 3, Planner.withTimetable([wtc(6), s33(1)], at: Station.byID["NEW"]!, now: now)))),
            ("home-nothing-posted", .plan(plan("NEW", walk: 1, Planner.withTimetable([], at: Station.byID["NEW"]!, now: now)))),
            ("empty", .plan(.sample(at: now, stationID: "EXP", walkMinutes: 5, minutes: []))),
            ("stale", .failed(message: "Couldn't load trains", stale: .sample(at: now, stationID: "HOB", walkMinutes: 7, minutes: [11, 21],
                                                                                colors: "65C100", headsign: "World Trade Center"))),
            ("needs-location", .needsLocation),
            ("failed", .failed(message: "Couldn't load trains", stale: nil)),
        ]
    }

    private func tile(_ state: BoardState, _ family: WidgetFamily, _ size: CGSize, _ mode: Mode) -> some View {
        let lock = [.accessoryInline, .accessoryCircular, .accessoryRectangular].contains(family)
        let rendering: WidgetRenderingMode = lock ? .vibrant : (mode == .tinted ? .accented : .fullColor)
        return BoardView(entry: BoardEntry(date: now, state: state), family: family)
            .environment(\.widgetRenderingMode, rendering)
            .environment(\.colorScheme, mode == .light && !lock ? .light : .dark)
            .padding(lock ? 0 : 16)  // WidgetKit's default content margins
            .frame(width: size.width, height: size.height)
            .background {
                if lock { Color.black.opacity(0.85) }
                else if mode == .tinted { Color(white: 0.16) }
                else { mode == .dark ? Color(white: 0.11) : Color.white }
            }
            .clipShape(RoundedRectangle(cornerRadius: lock ? 12 : 22, style: .continuous))
    }

    private func sheet(_ state: BoardState) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Mode.allCases, id: \.self) { mode in
                HStack(alignment: .top, spacing: 14) {
                    ForEach(Self.small, id: \.self) { s in self.tile(state, .systemSmall, CGSize(width: s, height: s), mode) }
                    ForEach(Self.medium, id: \.width) { s in self.tile(state, .systemMedium, s, mode) }
                }
            }
            HStack(alignment: .top, spacing: 14) {
                tile(state, .accessoryRectangular, CGSize(width: 158, height: 72), .dark)
                tile(state, .accessoryRectangular, CGSize(width: 172, height: 76), .dark)
                tile(state, .accessoryCircular, CGSize(width: 72, height: 72), .dark)
                tile(state, .accessoryInline, CGSize(width: 230, height: 22), .dark)
            }
        }
        .padding(20)
        .background(Color(white: 0.55))
    }

    /// Train Rings: small and medium, full color and tinted.
    private func glassSheet(_ state: BoardState) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach([true, false], id: \.self) { full in
                let rendering: WidgetRenderingMode = full ? .fullColor : .accented
                HStack(alignment: .top, spacing: 14) {
                    ForEach(Self.small, id: \.self) { s in self.glassTile(state, .systemSmall, CGSize(width: s, height: s), rendering) }
                    ForEach(Self.medium, id: \.width) { s in self.glassTile(state, .systemMedium, s, rendering) }
                }
            }
        }
        .padding(20)
        .background(LinearGradient(colors: [Color(red: 0.45, green: 0.55, blue: 0.6), Color(red: 0.3, green: 0.32, blue: 0.3)],
                                   startPoint: .top, endPoint: .bottom))
    }

    private func glassTile(_ state: BoardState, _ family: WidgetFamily, _ size: CGSize, _ rendering: WidgetRenderingMode) -> some View {
        GlassBoardView(entry: BoardEntry(date: now, state: state), family: family)
            .environment(\.widgetRenderingMode, rendering)
            .environment(\.colorScheme, .dark)
            .padding(16)
            .frame(width: size.width, height: size.height)
            .background { if rendering == .accented { Color(white: 0.16) } else { GlassBackground() } }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    func testRenderContactSheets() throws {
        guard let dir = ProcessInfo.processInfo.environment["RENDER_DIR"] else {
            throw XCTSkip("set TEST_RUNNER_RENDER_DIR to render contact sheets")
        }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let saved = SharedStore.newportDestinationIDs
        defer { SharedStore.newportDestinationIDs = saved }
        let home = scenarios().first { $0.0 == "home" }!.1
        var all: [(String, BoardState, [String])] = scenarios().map { ($0.0, $0.1, Destination.defaultNewportIDs) }
        all.append(("home-all-four", home, Destination.newport.map(\.id)))
        all.append(("home-wtc-only", home, ["WTC"]))
        for (name, state, ids) in all {
            SharedStore.newportDestinationIDs = ids
            let renderer = ImageRenderer(content: sheet(state))
            renderer.scale = 2
            let data = try XCTUnwrap(renderer.uiImage?.pngData(), name)
            try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
            let glass = ImageRenderer(content: glassSheet(state))
            glass.scale = 2
            try XCTUnwrap(glass.uiImage?.pngData(), name)
                .write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name)-glass.png"))
        }
    }
}
