import BarStateCore
import Foundation

protocol MonitorValueFetching: Sendable {
    func fetchValue(for monitor: Monitor) async -> FetchOutcome
}

struct PollingStatus: Equatable, Sendable {
    var revision: UInt64 = 0
    var refreshingIDs: Set<UUID> = []
    var nextRefreshAt: [UUID: Date] = [:]

    var isRefreshing: Bool { !refreshingIDs.isEmpty }
}

actor PollingEngine {
    typealias ResultHandler = @Sendable (
        UUID,
        FetchOutcome,
        Date
    ) async -> Void
    typealias StatusHandler = @Sendable (PollingStatus) -> Void

    private struct RunningRequest {
        let generation: UInt64
        let task: Task<Void, Never>
    }

    private let valueFetcher: any MonitorValueFetching
    private let resultHandler: ResultHandler
    private let statusHandler: StatusHandler
    private let maximumConcurrentRequests: Int
    private var monitors: [UUID: Monitor] = [:]
    private var nextDue: [UUID: Date] = [:]
    private var running: [UUID: RunningRequest] = [:]
    private var generations: [UUID: UInt64] = [:]
    private var statusRevision: UInt64 = 0
    private var loopTask: Task<Void, Never>?

    init(
        valueFetcher: any MonitorValueFetching,
        maximumConcurrentRequests: Int = 4,
        resultHandler: @escaping ResultHandler,
        statusHandler: @escaping StatusHandler = { _ in }
    ) {
        self.valueFetcher = valueFetcher
        self.maximumConcurrentRequests = max(1, maximumConcurrentRequests)
        self.resultHandler = resultHandler
        self.statusHandler = statusHandler
    }

    func update(monitors newMonitors: [Monitor], refreshChanged: Bool = true) {
        let enabled = newMonitors.filter(\.isEnabled)
        let newByID = Dictionary(uniqueKeysWithValues: enabled.map { ($0.id, $0) })
        let oldByID = monitors
        let removedIDs = Set(oldByID.keys).subtracting(newByID.keys)

        for id in removedIDs {
            invalidateRequest(for: id)
            nextDue.removeValue(forKey: id)
        }

        monitors = newByID
        let now = Date()
        for monitor in enabled {
            if let oldMonitor = oldByID[monitor.id] {
                if Self.requestConfigurationChanged(from: oldMonitor, to: monitor) {
                    invalidateRequest(for: monitor.id)
                    nextDue[monitor.id] = refreshChanged
                        ? now
                        : now.addingTimeInterval(monitor.refreshInterval)
                } else if nextDue[monitor.id] == nil, running[monitor.id] == nil {
                    nextDue[monitor.id] = now.addingTimeInterval(monitor.refreshInterval)
                }
            } else {
                generations[monitor.id, default: 0] &+= 1
                nextDue[monitor.id] = refreshChanged
                    ? now
                    : now.addingTimeInterval(monitor.refreshInterval)
            }
        }

        launchDueRequests(at: now)
    }

    func refreshAll() {
        let now = Date()
        for id in monitors.keys {
            nextDue[id] = now
        }
        launchDueRequests(at: now)
    }

    func refreshOverdue() {
        launchDueRequests(at: Date())
    }

    func refreshAfterConnectivityRestored() {
        let now = Date()
        for id in monitors.keys where running[id] == nil {
            nextDue[id] = now
        }
        launchDueRequests(at: now)
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
        for request in running.values {
            request.task.cancel()
        }
        running.removeAll()
        nextDue.removeAll()
        publishStatus()
    }

    private func invalidateRequest(for id: UUID) {
        generations[id, default: 0] &+= 1
        running.removeValue(forKey: id)?.task.cancel()
    }

    private func launchDueRequests(at date: Date) {
        loopTask?.cancel()
        loopTask = nil

        while running.count < maximumConcurrentRequests {
            guard let candidate = nextDue
                .filter({ $0.value <= date && running[$0.key] == nil })
                .min(by: { lhs, rhs in
                    if lhs.value == rhs.value {
                        return (monitors[lhs.key]?.order ?? 0) < (monitors[rhs.key]?.order ?? 0)
                    }
                    return lhs.value < rhs.value
                }),
                let monitor = monitors[candidate.key]
            else { break }

            nextDue.removeValue(forKey: monitor.id)
            launch(monitor)
        }

        publishStatus()
        rescheduleLoop()
    }

    private func launch(_ monitor: Monitor) {
        guard running[monitor.id] == nil else { return }
        let generation = generations[monitor.id, default: 0]
        let valueFetcher = self.valueFetcher

        let task = Task { [weak self] in
            let outcome = await valueFetcher.fetchValue(for: monitor)
            await self?.finish(
                monitorID: monitor.id,
                generation: generation,
                outcome: outcome,
                at: Date()
            )
        }
        running[monitor.id] = RunningRequest(generation: generation, task: task)
    }

    private func finish(
        monitorID: UUID,
        generation: UInt64,
        outcome: FetchOutcome,
        at date: Date
    ) async {
        guard let request = running[monitorID], request.generation == generation else {
            return
        }
        running.removeValue(forKey: monitorID)

        guard generations[monitorID, default: 0] == generation,
              let monitor = monitors[monitorID]
        else {
            launchDueRequests(at: date)
            return
        }

        if nextDue[monitorID] == nil {
            nextDue[monitorID] = date.addingTimeInterval(monitor.refreshInterval)
        }
        await resultHandler(monitorID, outcome, date)
        launchDueRequests(at: date)
    }

    private func rescheduleLoop() {
        loopTask?.cancel()

        guard running.count < maximumConcurrentRequests,
              let earliest = nextDue
                .filter({ running[$0.key] == nil })
                .map(\.value)
                .min()
        else {
            loopTask = nil
            return
        }

        let seconds = min(
            max(0.1, earliest.timeIntervalSinceNow),
            Monitor.maximumRefreshInterval
        )
        let nanoseconds = UInt64(seconds * 1_000_000_000)
        loopTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            await self?.refreshOverdue()
        }
    }

    private func publishStatus() {
        statusRevision &+= 1
        statusHandler(
            PollingStatus(
                revision: statusRevision,
                refreshingIDs: Set(running.keys),
                nextRefreshAt: nextDue
            )
        )
    }

    private static func requestConfigurationChanged(from old: Monitor, to new: Monitor) -> Bool {
        old.sourceKind != new.sourceKind
            || old.urlString != new.urlString
            || old.promQL != new.promQL
            || old.requestHeaders != new.requestHeaders
            || old.parser != new.parser
            || old.requestTimeout != new.requestTimeout
            || old.refreshInterval != new.refreshInterval
    }
}
