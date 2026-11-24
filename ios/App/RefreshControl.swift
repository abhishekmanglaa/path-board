import Foundation

/// Cancellation plus a generation check: a dependency that ignores cancellation
/// still cannot replace a newer station or result.
@MainActor
final class LatestPlanRequest {
    private var generation = 0
    private var task: Task<Plan, Error>?

    func run(_ operation: @escaping () async throws -> Plan) async throws -> Plan? {
        guard !Task.isCancelled else { return nil }
        cancel()
        let request = generation
        let pending = Task { try await operation() }
        task = pending
        do {
            let value = try await pending.value
            guard request == generation, !Task.isCancelled else { return nil }
            task = nil
            return value
        } catch {
            guard request == generation, !Task.isCancelled else { return nil }
            task = nil
            if error is CancellationError { return nil }
            throw error
        }
    }

    func cancel() {
        generation += 1
        task?.cancel()
        task = nil
    }
}

@MainActor
final class ForegroundPoller {
    private var task: Task<Void, Never>?

    func start(interval: Duration = .seconds(30), immediately: Bool = false,
               nextInterval: (@MainActor () -> Duration)? = nil,
               action: @escaping @MainActor () async -> Void) {
        stop()
        task = Task {
            guard !Task.isCancelled else { return }
            if immediately { await action() }
            while !Task.isCancelled {
                do { try await Task.sleep(for: nextInterval?() ?? interval) } catch { return }
                guard !Task.isCancelled else { return }
                await action()
            }
        }
    }

    func stop() { task?.cancel(); task = nil }
    deinit { task?.cancel() }
}
