import Foundation

/// Coalesces alert requests in each process and shares successful snapshots
/// between the app and widget. The planner drives all refreshes.
actor ServiceAlertClient {
    private let fetch: @Sendable () async throws -> Data
    private var lastAttempt: Date?
    private var latest: ServiceAlertSnapshot?
    private var inFlight: Task<ServiceAlertSnapshot?, Never>?

    init(fetch: @escaping @Sendable () async throws -> Data) {
        self.fetch = fetch
    }

    func snapshot(cached: ServiceAlertSnapshot?, at now: Date) async -> ServiceAlertSnapshot? {
        if let inFlight { return await inFlight.value }
        let fallback = [latest, cached].compactMap { $0 }.filter {
            $0.fetchedAt.timeIntervalSince(now) <= 5
        }.max { $0.fetchedAt < $1.fetchedAt }
        if let fallback, now.timeIntervalSince(fallback.fetchedAt) < ServiceAlertSnapshot.refreshInterval {
            return fallback
        }
        if let lastAttempt, now >= lastAttempt,
           now.timeIntervalSince(lastAttempt) < ServiceAlertSnapshot.refreshInterval {
            return fallback
        }
        lastAttempt = now
        let task = Task<ServiceAlertSnapshot?, Never> { [fetch] in
            do {
                let data = try await fetch()
                return try ServiceAlertSnapshot.decode(data, fetchedAt: now)
            } catch {
                return fallback
            }
        }
        inFlight = task
        let result = await task.value
        latest = result
        inFlight = nil
        return result
    }

    private static let live = ServiceAlertClient {
        let url = URL(string: "https://www.panynj.gov/bin/portauthority/alerts?agency=PATH&hours=24")!
        let (data, response) = try await session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 6
        config.timeoutIntervalForResource = 8
        return URLSession(configuration: config)
    }()

    static func current() async -> ServiceAlertSnapshot? {
        let snapshot = await live.snapshot(cached: SharedStore.serviceAlerts, at: .now)
        if let snapshot { SharedStore.saveServiceAlerts(snapshot) }
        return snapshot
    }
}
