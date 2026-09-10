import BarStateCore
import Combine
import Foundation

@MainActor
final class MonitorStore: ObservableObject {
    private struct ManualRefreshContext {
        let monitorIDs: Set<UUID>
        let startedAt: Date
    }

    @Published private(set) var monitors: [Monitor]
    @Published private(set) var pollingStatus = PollingStatus()
    @Published private(set) var refreshFeedback: String?
    @Published private(set) var persistenceMessage: String?
    @Published private(set) var preferences: AppPreferences
    @Published private(set) var recoveryMode: PersistenceRecoveryMode?
    @Published private(set) var now = Date()
    @Published private(set) var isNetworkOffline = false
    @Published var notificationPermission: NotificationPermission = .unknown
    @Published var notificationMessage: String?
    var onConfigurationChange: (([Monitor]) -> Void)?
    var onAlert: ((Monitor, MonitorAlertEvent) -> Void)?
    var onRequestNotificationPermission: (() -> Void)?

    private let persistence: PersistenceController
    private let persistenceWriter: PersistenceWriter
    private let persistsChanges: Bool
    private var saveTask: Task<Void, Never>?
    private var refreshFeedbackTask: Task<Void, Never>?
    private var manualRefreshContext: ManualRefreshContext?
    private var persistenceRevision = 0

    init(
        persistence: PersistenceController = PersistenceController(),
        initialMonitors: [Monitor]? = nil
    ) {
        let loadResult = persistence.load()
        self.persistence = persistence
        self.persistenceWriter = PersistenceWriter(persistence: persistence)
        self.persistsChanges = initialMonitors == nil
        self.monitors = (initialMonitors ?? loadResult.state.monitors)
            .sorted { $0.order < $1.order }
        self.preferences = initialMonitors == nil ? loadResult.state.preferences : .init()
        self.persistenceMessage = initialMonitors == nil ? loadResult.warning : nil
        self.recoveryMode = initialMonitors == nil ? loadResult.recoveryMode : nil
        for index in monitors.indices { monitors[index].runtime.alertState.interruptSamples() }
        normalizeOrder()
    }

    var orderedMonitors: [Monitor] {
        monitors.sorted { $0.order < $1.order }
    }

    var isPersistenceWriteProtected: Bool {
        recoveryMode != nil
    }

    var configurationDirectoryURL: URL {
        persistence.directoryURL
    }

    func monitor(id: UUID) -> Monitor? {
        monitors.first { $0.id == id }
    }

    func tick(at date: Date = Date()) {
        // Time alone must not redraw every form and status item. Publish only a health transition.
        if monitors.contains(where: {
            MonitorHealth(monitor: $0, now: now) != MonitorHealth(monitor: $0, now: date)
        }) { now = date }
    }

    func health(for monitor: Monitor) -> MonitorHealth {
        MonitorHealth(monitor: monitor, now: now,
                      isRefreshing: pollingStatus.refreshingIDs.contains(monitor.id),
                      isNetworkOffline: isNetworkOffline)
    }

    func setNetworkOffline(_ offline: Bool) {
        guard offline != isNetworkOffline else { return }
        isNetworkOffline = offline
        if offline {
            for index in monitors.indices where !monitors[index].usesLoopbackConnection {
                monitors[index].runtime.alertState.interruptSamples()
            }
        }
        tick()
    }

    func add(_ monitor: Monitor) {
        guard !isPersistenceWriteProtected else { return }
        guard !monitors.contains(where: { $0.id == monitor.id }) else { return }
        var normalized = monitor
        normalized.refreshInterval = Monitor.normalizedRefreshInterval(monitor.refreshInterval)
        normalized.requestTimeout = Monitor.normalizedRequestTimeout(monitor.requestTimeout)
        normalized.order = monitors.count
        monitors.append(normalized)
        configurationsDidChange()
    }

    func update(_ monitor: Monitor) {
        guard !isPersistenceWriteProtected else { return }
        guard let index = monitors.firstIndex(where: { $0.id == monitor.id }) else { return }
        var normalized = monitor
        // Ordering can change while this monitor's editor still holds an older draft.
        normalized.order = monitors[index].order
        normalized.refreshInterval = Monitor.normalizedRefreshInterval(monitor.refreshInterval)
        normalized.requestTimeout = Monitor.normalizedRequestTimeout(monitor.requestTimeout)
        if !monitors[index].hasSameValueConfiguration(as: normalized) {
            var alertState = monitors[index].runtime.alertState
            alertState.reset()
            normalized.runtime = .init()
            normalized.runtime.alertState = alertState
        } else {
            normalized.runtime = monitors[index].runtime
            if monitors[index].alertRule != normalized.alertRule
                || monitors[index].isEnabled != normalized.isEnabled {
                normalized.runtime.alertState.reset()
            }
        }
        monitors[index] = normalized
        normalizeOrder()
        configurationsDidChange()
    }

    func updateSwitches(
        id: UUID,
        isEnabled: Bool,
        showsInMenuBar: Bool
    ) {
        guard !isPersistenceWriteProtected else { return }
        guard let index = monitors.firstIndex(where: { $0.id == id }) else { return }
        guard monitors[index].isEnabled != isEnabled
            || monitors[index].showsInMenuBar != showsInMenuBar
        else { return }

        if monitors[index].isEnabled != isEnabled { monitors[index].runtime.alertState.reset() }
        monitors[index].isEnabled = isEnabled
        monitors[index].showsInMenuBar = showsInMenuBar
        configurationsDidChange()
    }

    func remove(id: UUID) {
        guard !isPersistenceWriteProtected else { return }
        monitors.removeAll { $0.id == id }
        normalizeOrder()
        configurationsDidChange()
    }

    func move(id: UUID, offset: Int) {
        guard !isPersistenceWriteProtected else { return }
        var ordered = orderedMonitors
        guard let source = ordered.firstIndex(where: { $0.id == id }) else { return }
        let destination = min(max(0, source + offset), ordered.count - 1)
        guard source != destination else { return }
        let monitor = ordered.remove(at: source)
        ordered.insert(monitor, at: destination)
        applyMonitorOrder(ordered)
    }

    func move(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        guard !isPersistenceWriteProtected else { return }
        var ordered = orderedMonitors
        let moving = offsets.sorted().map { ordered[$0] }
        for index in offsets.sorted(by: >) {
            ordered.remove(at: index)
        }
        let removedBeforeDestination = offsets.filter { $0 < destination }.count
        let insertionIndex = min(
            max(0, destination - removedBeforeDestination),
            ordered.count
        )
        ordered.insert(contentsOf: moving, at: insertionIndex)
        applyMonitorOrder(ordered)
    }

    func updatePreferences(_ preferences: AppPreferences) {
        guard !isPersistenceWriteProtected else { return }
        var normalized = preferences
        normalized.menuBarMaximumCharacters = AppPreferences.normalizedMenuBarCharacters(
            preferences.menuBarMaximumCharacters
        )
        guard normalized != self.preferences else { return }
        self.preferences = normalized
        saveImmediately()
    }

    func record(
        requestedMonitor: Monitor,
        result: Result<Double, MonitoringError>,
        at date: Date,
        response: HTTPResponseSnapshot?,
        requestDuration: TimeInterval? = nil
    ) {
        // Recheck on the main actor: settings may change while a result is delivered.
        guard !isPersistenceWriteProtected, let current = monitor(id: requestedMonitor.id),
              current.isEnabled,
              current.hasSameValueConfiguration(as: requestedMonitor)
        else { return }
        record(monitorID: current.id, result: result, at: date, response: response,
               requestDuration: requestDuration)
        guard let index = monitors.firstIndex(where: { $0.id == current.id }) else { return }
        // Offline remote samples are still recorded for diagnostics, but never open incidents.
        guard !isNetworkOffline || current.usesLoopbackConnection else {
            monitors[index].runtime.alertState.interruptSamples()
            return
        }
        // A rule changed during this request must start with a new request after the edit.
        guard current.alertRule == requestedMonitor.alertRule else { return }
        let event = monitors[index].runtime.alertState.evaluate(
            result, rule: current.alertRule, at: date,
            allowsNotification: notificationPermission == .authorized
        )
        if let event {
            persistAndDeliver(event, monitor: monitors[index])
        } else { scheduleSave() }
    }

    private func persistAndDeliver(_ event: MonitorAlertEvent, monitor: Monitor) {
        saveTask?.cancel()
        persistenceRevision += 1
        let revision = persistenceRevision
        let snapshot = storedStateSnapshot
        Task { @MainActor [weak self] in
            guard let self else { return }
            // Persist deduplication before submitting to Notification Center.
            if self.persistsChanges {
                do { _ = try await self.persistenceWriter.save(state: snapshot, revision: revision) }
                catch {
                    self.persistenceMessage = L10n.format("persistence.save_failed", error.localizedDescription)
                    return
                }
            }
            guard self.canDeliver(event, for: monitor) else { return }
            self.onAlert?(monitor, event)
        }
    }

    func canDeliver(_ event: MonitorAlertEvent, for requested: Monitor) -> Bool {
        guard !isPersistenceWriteProtected, notificationPermission == .authorized,
              let current = monitor(id: requested.id), current.isEnabled,
              current.alertRule.isEnabled, current.alertRule == requested.alertRule,
              current.hasSameValueConfiguration(as: requested),
              current.runtime.alertState.contains(event),
              !isNetworkOffline || current.usesLoopbackConnection else { return false }
        return true
    }

    func record(
        monitorID: UUID,
        result: Result<Double, MonitoringError>,
        at date: Date,
        response: HTTPResponseSnapshot?,
        requestDuration: TimeInterval? = nil
    ) {
        guard !isPersistenceWriteProtected else { return }
        guard let index = monitors.firstIndex(where: { $0.id == monitorID }) else { return }
        switch result {
        case let .success(value):
            monitors[index].runtime.recordSuccess(
                value,
                at: date,
                response: response,
                requestDuration: requestDuration
            )
        case let .failure(error):
            monitors[index].runtime.recordFailure(
                error,
                at: date,
                response: response,
                requestDuration: requestDuration
            )
        }
        tick(at: date)
        scheduleSave()
    }

    func setPollingStatus(_ status: PollingStatus) {
        guard status.revision >= pollingStatus.revision else { return }
        let completedRefresh = pollingStatus.isRefreshing && !status.isRefreshing
        pollingStatus = status
        if completedRefresh, let context = manualRefreshContext {
            manualRefreshContext = nil
            refreshFeedback = manualRefreshSummary(for: context)
            scheduleRefreshFeedbackClear()
        } else if status.isRefreshing, manualRefreshContext != nil {
            refreshFeedbackTask?.cancel()
            refreshFeedback = nil
        }
    }

    @discardableResult
    func beginManualRefresh() -> Bool {
        guard !isPersistenceWriteProtected else {
            refreshFeedback = L10n.string("persistence.recovery_required")
            return false
        }
        guard !pollingStatus.isRefreshing else { return false }
        let enabledIDs = Set(monitors.lazy.filter(\.isEnabled).map(\.id))
        guard !enabledIDs.isEmpty else {
            refreshFeedback = L10n.string("refresh.none")
            scheduleRefreshFeedbackClear()
            return false
        }

        refreshFeedbackTask?.cancel()
        refreshFeedback = nil
        manualRefreshContext = ManualRefreshContext(
            monitorIDs: enabledIDs,
            startedAt: Date()
        )
        return true
    }

    func flushPersistence() async {
        guard persistsChanges, !isPersistenceWriteProtected else { return }
        saveTask?.cancel()
        saveTask = nil
        persistenceRevision += 1
        await save(state: storedStateSnapshot, revision: persistenceRevision)
    }

    func restoreRecoveredConfiguration() async {
        guard let recoveryMode else { return }
        await resolveRecovery(
            state: storedStateSnapshot,
            mode: recoveryMode
        )
    }

    func startFreshAfterRecovery() async {
        guard recoveryMode == .unreadableFiles else { return }
        let freshState = StoredState(monitors: [], preferences: preferences)
        guard await resolveRecovery(state: freshState, mode: .unreadableFiles) else { return }
        monitors = []
        normalizeOrder()
    }

    func exportConfiguration(to destinationURL: URL) throws {
        try persistence.export(state: storedStateSnapshot, to: destinationURL)
    }

    private func configurationsDidChange() {
        guard !isPersistenceWriteProtected else { return }
        saveImmediately()
        onConfigurationChange?(orderedMonitors)
    }

    private func manualRefreshSummary(for context: ManualRefreshContext) -> String {
        let completed = monitors.filter { monitor in
            context.monitorIDs.contains(monitor.id)
                && monitor.runtime.lastAttemptAt.map { $0 >= context.startedAt } == true
        }
        let failureCount = completed.filter { $0.runtime.consecutiveFailures > 0 }.count
        let successCount = completed.count - failureCount
        let pendingCount = context.monitorIDs.count - completed.count

        if failureCount == 0, pendingCount == 0 {
            return L10n.plural("refresh.success", count: successCount)
        }

        var parts = [
            L10n.format("refresh.success_part", Int64(successCount)),
            L10n.format("refresh.failure_part", Int64(failureCount))
        ]
        if pendingCount > 0 {
            parts.append(L10n.format("refresh.pending_part", Int64(pendingCount)))
        }
        return L10n.format(
            "refresh.summary",
            parts.joined(separator: L10n.string("list.accessibility_separator"))
        )
    }

    private func scheduleRefreshFeedbackClear() {
        refreshFeedbackTask?.cancel()
        refreshFeedbackTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            self?.refreshFeedback = nil
        }
    }

    private func applyMonitorOrder(_ ordered: [Monitor]) {
        monitors = ordered.enumerated().map { index, monitor in
            var updated = monitor
            updated.order = index
            return updated
        }
        configurationsDidChange()
    }

    private func normalizeOrder() {
        monitors.sort { $0.order < $1.order }
        for index in monitors.indices {
            monitors[index].order = index
        }
    }

    private func scheduleSave() {
        guard persistsChanges, !isPersistenceWriteProtected else { return }
        saveTask?.cancel()
        persistenceRevision += 1
        let revision = persistenceRevision
        let snapshot = storedStateSnapshot
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await self?.save(state: snapshot, revision: revision)
        }
    }

    private func saveImmediately() {
        guard persistsChanges, !isPersistenceWriteProtected else { return }
        saveTask?.cancel()
        persistenceRevision += 1
        let revision = persistenceRevision
        let snapshot = storedStateSnapshot
        saveTask = Task { @MainActor [weak self] in
            await self?.save(state: snapshot, revision: revision)
        }
    }

    private var storedStateSnapshot: StoredState {
        StoredState(monitors: monitors, preferences: preferences)
    }

    @discardableResult
    private func resolveRecovery(
        state: StoredState,
        mode: PersistenceRecoveryMode
    ) async -> Bool {
        saveTask?.cancel()
        persistenceRevision += 1
        do {
            _ = try await persistenceWriter.resolveRecovery(
                state: state,
                mode: mode,
                revision: persistenceRevision
            )
            preferences = state.preferences
            recoveryMode = nil
            persistenceMessage = L10n.string("persistence.recovery_complete")
            onConfigurationChange?(state.monitors.sorted { $0.order < $1.order })
            return true
        } catch {
            persistenceMessage = L10n.format(
                "persistence.recovery_failed",
                error.localizedDescription
            )
            return false
        }
    }

    private func save(state: StoredState, revision: Int) async {
        do {
            if try await persistenceWriter.save(state: state, revision: revision) {
                persistenceMessage = nil
            }
        } catch {
            persistenceMessage = L10n.format(
                "persistence.save_failed",
                error.localizedDescription
            )
        }
    }
}
