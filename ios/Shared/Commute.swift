import Foundation

enum PlanFreshness: Equatable {
    case fresh, aging, expired

    init(asOf: Date, now: Date) {
        let age = now.timeIntervalSince(asOf)
        self = age < -5 || age >= 300 ? .expired : age >= 120 ? .aging : .fresh
    }
}

struct CommuteRecommendation: Hashable {
    let departure: Departure
    let leaveAt: Date
    let walkMinutes: Int
    let bufferMinutes: Int
    let skippedTightTrain: Bool

    func leaveInMinutes(at now: Date) -> Int {
        max(0, Int(floor(leaveAt.timeIntervalSince(now) / 60)))
    }

    static func make(plan: Plan, now: Date, bufferMinutes: Int,
                     destinations: [Destination] = SharedStore.newportDestinations,
                     offline: Bool = false) -> Self? {
        guard !offline, plan.freshness(at: now) != .expired, plan.hasReliableWalk(at: now) else { return nil }
        let buffer = min(3, max(1, bufferMinutes))
        let needed = TimeInterval((plan.walkMinutes + buffer) * 60)
        let upcoming = plan.upcoming(at: now).filter { departure in
            !plan.station.isHome || destinations.contains { $0.includes(departure) }
        }
        guard let departure = upcoming.first(where: { $0.date.timeIntervalSince(now) >= needed }) else { return nil }
        return Self(departure: departure, leaveAt: departure.date.addingTimeInterval(-needed),
                    walkMinutes: plan.walkMinutes, bufferMinutes: buffer,
                    skippedTightTrain: upcoming.first != departure)
    }
}

struct WidgetOptions: Hashable {
    var stationID: String? = nil
    var destinationIDs: [String]? = nil
    var recommends = false

    var cacheKey: String { stationID ?? "automatic" }
    var destinations: [Destination] {
        let ids = destinationIDs ?? SharedStore.newportDestinationIDs
        return Destination.newport.filter { ids.contains($0.id) }
    }

    func canRecommend(plan: Plan, at date: Date, isAccessory: Bool) -> Bool {
        recommends && (!isAccessory || plan.freshness(at: date) == .fresh)
    }
}

extension Plan {
    static let walkAdviceAge: TimeInterval = 5 * 60
    static let savedWalkAge: TimeInterval = 60 * 60

    var asOf: Date { predictionDate ?? computedAt }
    var walkMeasuredAt: Date { locationDate ?? computedAt }
    func freshness(at now: Date) -> PlanFreshness { PlanFreshness(asOf: asOf, now: now) }
    func hasReliableWalk(at now: Date) -> Bool {
        !walkIsSaved && hasDisplayWalk(at: now) && now.timeIntervalSince(walkMeasuredAt) <= Self.walkAdviceAge
    }
    func hasDisplayWalk(at now: Date) -> Bool {
        let age = now.timeIntervalSince(walkMeasuredAt)
        return walkIsKnown && age >= -5 && age < Self.savedWalkAge && walkSeconds.isFinite && walkSeconds >= 0
    }
    func freshnessText(at now: Date, offline: Bool = false) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(asOf)))
        let age = seconds < 60 ? "just now" : "\(seconds / 60)m ago"
        if offline { return "Offline · updated \(age)" }
        switch freshness(at: now) {
        case .fresh: return "Updated \(age)"
        case .aging: return "Older prediction · \(age)"
        case .expired: return "Prediction expired · refresh to check"
        }
    }
}
