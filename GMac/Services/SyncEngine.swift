import Foundation
import Observation

@Observable
@MainActor
final class SyncEngine {
    private(set) var isRunning = false
    private var pollTask: Task<Void, Never>?
    private let store: SessionStore
    private let intervalSeconds: TimeInterval

    init(store: SessionStore, intervalSeconds: TimeInterval = 60) {
        self.store = store
        self.intervalSeconds = intervalSeconds
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.store.reconcile()
                try? await Task.sleep(for: .seconds(self.intervalSeconds))
            }
            await MainActor.run { self?.isRunning = false }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        isRunning = false
    }
}
