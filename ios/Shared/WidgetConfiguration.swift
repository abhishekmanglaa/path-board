import AppIntents
import SwiftUI

/// Stored values are station feed codes, stable across app updates.
enum WidgetStation: String, CaseIterable, AppEnum {
    case automatic, NWK, HAR, JSQ, GRV, NEW, EXP, HOB, WTC, CHR, s09 = "09S", s14 = "14S", s23 = "23S", s33 = "33S"
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Station"
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .automatic: "Follow my location", .NWK: "Newark", .HAR: "Harrison", .JSQ: "Journal Square",
        .GRV: "Grove Street", .NEW: "Newport", .EXP: "Exchange Place", .HOB: "Hoboken", .WTC: "World Trade Center",
        .CHR: "Christopher Street", .s09: "9th Street", .s14: "14th Street", .s23: "23rd Street", .s33: "33rd Street"
    ]
    var stationID: String? { self == .automatic ? nil : rawValue }
}

enum WidgetDirections: String, CaseIterable, AppEnum {
    case appSettings, all, wtc, s33, jsq, hob
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Newport directions"
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .appSettings: "Use app settings", .all: "All directions", .wtc: "World Trade Center",
        .s33: "33rd Street", .jsq: "Journal Square", .hob: "Hoboken"
    ]
    var ids: [String]? {
        switch self {
        case .appSettings: return nil
        case .all: return Destination.newport.map(\.id)
        case .wtc: return ["WTC"]
        case .s33: return ["33"]
        case .jsq: return ["JSQ"]
        case .hob: return ["HOB"]
        }
    }
}

enum WidgetDisplay: String, CaseIterable, AppEnum {
    case departures, recommendation
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Display"
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .departures: "Departure board", .recommendation: "When to leave"
    ]
}

struct BoardConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Train Home"
    static var description = IntentDescription("Choose this widget's station, Newport directions, and display.")
    @Parameter(title: "Station", default: .automatic) var station: WidgetStation
    @Parameter(title: "Newport directions", default: .appSettings) var directions: WidgetDirections
    @Parameter(title: "Display", default: .departures) var display: WidgetDisplay
    var options: WidgetOptions {
        WidgetOptions(stationID: station.stationID, destinationIDs: directions.ids, recommends: display == .recommendation)
    }
}

private struct RefreshStationKey: EnvironmentKey { static let defaultValue = "" }
extension EnvironmentValues {
    var refreshStationID: String {
        get { self[RefreshStationKey.self] }
        set { self[RefreshStationKey.self] = newValue }
    }
}
