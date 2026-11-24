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
        let homebound = Departure(date: now.addingTimeInterval(6 * 60), headsign: "Journal Square", lineColors: "FF9900")
        let hoboken = Departure(date: now.addingTimeInterval(4 * 60), headsign: "Hoboken", lineColors: "4D92FB")
        func plan(_ id: String, walk: Double, _ deps: [Departure]) -> Plan {
            let st = Station.byID[id]!
            return Plan(stationID: id, walkSeconds: walk * 60, departures: deps, computedAt: now,
                        originLatitude: st.latitude, originLongitude: st.longitude)
        }
        return [
            ("penn-two-both-lines", .plan(plan("33S", walk: 6, Planner.withTimetable([hoboken, homebound], at: Station.byID["33S"]!, now: now)))),
            ("penn-two-hoboken-between-postings", .plan(plan("33S", walk: 6, Planner.withTimetable([homebound], at: Station.byID["33S"]!, now: now)))),
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
            ("far-away", .farAway),
            ("newark-change", .plan(.sample(at: now, stationID: "NWK", walkMinutes: 2, minutes: [6, 21],
                                            colors: "D93A30", headsign: "World Trade Center"))),
        ]
    }

    private func tile(_ state: BoardState, _ showing: [Destination], _ family: WidgetFamily, _ size: CGSize, _ mode: Mode) -> some View {
        let lock = [.accessoryInline, .accessoryCircular, .accessoryRectangular].contains(family)
        let rendering: WidgetRenderingMode = lock ? .vibrant : (mode == .tinted ? .accented : .fullColor)
        return BoardView(entry: BoardEntry(date: now, state: state), family: family, showing: showing)
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

    private func sheet(_ state: BoardState, _ showing: [Destination]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Mode.allCases, id: \.self) { mode in
                HStack(alignment: .top, spacing: 14) {
                    ForEach(Self.small, id: \.self) { s in self.tile(state, showing, .systemSmall, CGSize(width: s, height: s), mode) }
                    ForEach(Self.medium, id: \.width) { s in self.tile(state, showing, .systemMedium, s, mode) }
                }
            }
            HStack(alignment: .top, spacing: 14) {
                tile(state, showing, .accessoryRectangular, CGSize(width: 158, height: 72), .dark)
                tile(state, showing, .accessoryRectangular, CGSize(width: 172, height: 76), .dark)
                tile(state, showing, .accessoryCircular, CGSize(width: 72, height: 72), .dark)
                tile(state, showing, .accessoryInline, CGSize(width: 230, height: 22), .dark)
            }
        }
        .padding(20)
        .background(Color(white: 0.55))
    }

    /// Train Rings: small and medium, full color and tinted.
    private func glassSheet(_ state: BoardState, _ showing: [Destination]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach([true, false], id: \.self) { full in
                let rendering: WidgetRenderingMode = full ? .fullColor : .accented
                HStack(alignment: .top, spacing: 14) {
                    ForEach(Self.small, id: \.self) { s in self.glassTile(state, showing, .systemSmall, CGSize(width: s, height: s), rendering) }
                    ForEach(Self.medium, id: \.width) { s in self.glassTile(state, showing, .systemMedium, s, rendering) }
                }
            }
        }
        .padding(20)
        .background(LinearGradient(colors: [Color(red: 0.45, green: 0.55, blue: 0.6), Color(red: 0.3, green: 0.32, blue: 0.3)],
                                   startPoint: .top, endPoint: .bottom))
    }

    private func glassTile(_ state: BoardState, _ showing: [Destination], _ family: WidgetFamily, _ size: CGSize,
                           _ rendering: WidgetRenderingMode) -> some View {
        GlassBoardView(entry: BoardEntry(date: now, state: state), family: family, showing: showing)
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
        let home = scenarios().first { $0.0 == "home" }!.1
        var all: [(String, BoardState, [String])] = scenarios().map { ($0.0, $0.1, Destination.defaultNewportIDs) }
        if case .plan(var newport) = home {
            newport.locationDate = now.addingTimeInterval(-420)
            newport.serviceAlerts = ServiceAlertSnapshot(fetchedAt: now, alerts: [
                ServiceAlert(id: "preview", title: "Hoboken–WTC service advisory", message: "Check platform signs.",
                             publishedAt: now, routes: [.hobokenWTC], stationIDs: [], systemWide: false)
            ])
            all.append(("newport-saved-walk", .plan(newport), Destination.newport.map(\.id)))
        }
        all.append(("home-all-four", home, Destination.newport.map(\.id)))
        all.append(("home-wtc-only", home, ["WTC"]))
        for (name, state, ids) in all {
            let showing = Destination.newport.filter { ids.contains($0.id) }
            let renderer = ImageRenderer(content: sheet(state, showing))
            renderer.scale = 2
            let data = try XCTUnwrap(renderer.uiImage?.pngData(), name)
            try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
            let glass = ImageRenderer(content: glassSheet(state, showing))
            glass.scale = 2
            try XCTUnwrap(glass.uiImage?.pngData(), name)
                .write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name)-glass.png"))
        }
    }

    func testRenderAppAndActivityStates() throws {
        guard let dir = ProcessInfo.processInfo.environment["RENDER_DIR"] else {
            throw XCTSkip("set TEST_RUNNER_RENDER_DIR to render app and Live Activity states")
        }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let plan = Plan.sample(at: now, stationID: "CHR", walkMinutes: 6, minutes: [4, 10, 20])
        for width: CGFloat in [320, 393] {
            for large in [false, true] {
                let content = VStack(alignment: .leading, spacing: 18) {
                    Text("Train Home").font(.largeTitle.bold())
                    Text("Christopher Street").font(.title2.bold())
                    CommuteDashboard(plan: plan, now: now)
                }
                .padding(20).frame(width: width)
                .background(Color(uiColor: .systemGroupedBackground))
                .environment(\.colorScheme, .light)
                .environment(\.dynamicTypeSize, large ? .accessibility3 : .large)
                let renderer = ImageRenderer(content: content)
                renderer.scale = 2
                let data = try XCTUnwrap(renderer.uiImage?.pngData())
                try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("app-\(Int(width))-\(large ? "large" : "normal").png"))
            }
        }
        for (name, date, offline, hasWalk) in [("expired", now.addingTimeInterval(301), false, true),
                                             ("offline", now, true, true), ("no-location", now, false, false)] {
            var state = plan
            state.walkIsKnown = hasWalk
            let renderer = ImageRenderer(content: CommuteDashboard(plan: state, now: date, offline: offline)
                .padding(20).frame(width: 393).background(Color(uiColor: .systemGroupedBackground)).environment(\.colorScheme, .dark))
            renderer.scale = 2
            try XCTUnwrap(renderer.uiImage?.pngData()).write(to: URL(fileURLWithPath: dir).appendingPathComponent("app-\(name).png"))
        }
        let livePlan = Plan.sample(at: Date(), stationID: "CHR", walkMinutes: 6, minutes: [4, 10, 20])
        let recommendation = try XCTUnwrap(CommuteRecommendation.make(plan: livePlan, now: Date(), bufferMinutes: 2))
        let state = CommuteActivity.ContentState(recommendation: recommendation, plan: livePlan)
        for stale in [false, true] {
            let renderer = ImageRenderer(content: CommuteActivityCard(state: state, stationName: "Christopher Street", isStale: stale)
                .frame(width: 393).background(Color(uiColor: .secondarySystemBackground)))
            renderer.scale = 2
            try XCTUnwrap(renderer.uiImage?.pngData()).write(to: URL(fileURLWithPath: dir).appendingPathComponent("activity-\(stale ? "stale" : "fresh").png"))
        }
        let options = WidgetOptions(stationID: "CHR", recommends: true)
        let renderer = ImageRenderer(content: ConfiguredBoard(entry: BoardEntry(date: now, state: .plan(plan), options: options), family: .systemSmall)
            .padding(16).frame(width: 170, height: 170).background(Color.white))
        renderer.scale = 2
        try XCTUnwrap(renderer.uiImage?.pngData()).write(to: URL(fileURLWithPath: dir).appendingPathComponent("widget-recommendation.png"))
    }

    func testLiveActivityFitsLockScreenHeight() throws {
        let date = Date()
        let plan = Plan.sample(at: date, stationID: "CHR", walkMinutes: 6, minutes: [12])
        let recommendation = try XCTUnwrap(CommuteRecommendation.make(plan: plan, now: date, bufferMinutes: 2))
        let state = CommuteActivity.ContentState(recommendation: recommendation, plan: plan)
        for width: CGFloat in [320, 393] {
            for stale in [false, true] {
                let renderer = ImageRenderer(content: CommuteActivityCard(state: state, stationName: "Christopher Street", isStale: stale)
                    .frame(width: width))
                let size = try XCTUnwrap(renderer.uiImage).size
                XCTAssertLessThanOrEqual(size.height, 130, "Reserve 30 points for the End tracking control within the 160pt Lock Screen limit")
            }
        }
    }
}
