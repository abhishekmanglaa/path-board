import AppIntents

struct RefreshTrainsIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh Trains"
    static var description = IntentDescription("Fetches fresh departures for this widget's station.")
    static var isDiscoverable = false
    @Parameter(title: "Station") var stationID: String

    init() { stationID = "" }
    init(stationID: String) { self.stationID = stationID }

    func perform() async throws -> some IntentResult {
        let options = WidgetOptions(stationID: stationID.isEmpty ? nil : stationID)
        _ = try? await WidgetPlanRefresh.load(options: options, forceFresh: true)
        return .result()
    }
}
