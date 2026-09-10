import BarStateCore
import Foundation
import Testing
@testable import BarState

@MainActor
struct AlertIntegrationTests {
    private func monitor(loopback: Bool = false) -> Monitor {
        Monitor(name: "A", sourceKind: loopback ? .prometheus : .httpAPI,
                urlString: loopback ? "http://127.0.0.1:9090" : "https://example.com/value",
                alertRule: .init(isEnabled: true, condition: .requestFailure, notifiesRecovery: true))
    }

    @Test func offlineSuppressesRemoteIncidentsButAllowsLoopback() {
        let remote = monitor()
        let local = monitor(loopback: true)
        let store = MonitorStore(initialMonitors: [remote, local])
        store.notificationPermission = .authorized
        store.setNetworkOffline(true)
        for _ in 0..<3 {
            store.record(requestedMonitor: remote, result: .failure(.requestTimedOut), at: Date(), response: nil)
            store.record(requestedMonitor: local, result: .failure(.requestTimedOut), at: Date(), response: nil)
        }
        #expect(store.monitor(id: remote.id)?.runtime.alertState.isActive == false)
        #expect(store.monitor(id: local.id)?.runtime.alertState.isActive == true)
        store.setNetworkOffline(false)
        store.record(requestedMonitor: remote, result: .failure(.requestTimedOut), at: Date(), response: nil)
        #expect(store.monitor(id: remote.id)?.runtime.alertState.isActive == false)
        store.record(requestedMonitor: remote, result: .success(0), at: Date(), response: nil)
        #expect(store.monitor(id: remote.id)?.runtime.consecutiveFailures == 0)
    }

    @Test func runtimeRecordingWithoutRequestProvenanceDoesNotEvaluateAlerts() {
        let monitor = monitor()
        let store = MonitorStore(initialMonitors: [monitor])
        for _ in 0..<5 {
            store.record(monitorID: monitor.id, result: .failure(.requestTimedOut), at: Date(), response: nil)
        }
        #expect(store.monitor(id: monitor.id)?.runtime.alertState.isActive == false)
    }

    @Test func changedRuleAndDisabledDeletedMonitorRejectPendingNotification() throws {
        let monitor = monitor()
        let store = MonitorStore(initialMonitors: [monitor])
        store.notificationPermission = .authorized
        for _ in 0..<3 {
            store.record(requestedMonitor: monitor, result: .failure(.requestTimedOut), at: Date(), response: nil)
        }
        let current = try #require(store.monitor(id: monitor.id))
        let incidentID = try #require(current.runtime.alertState.incidentID)
        let event = MonitorAlertEvent(kind: .abnormal, incidentID: incidentID, value: nil)
        #expect(store.canDeliver(event, for: current))
        var edited = current
        edited.alertRule.condition = .belowOrEqual
        store.update(edited)
        #expect(!store.canDeliver(event, for: current))
        store.record(requestedMonitor: current, result: .success(0), at: Date(), response: nil)
        #expect(store.monitor(id: current.id)?.runtime.alertState.abnormalSamples == 0)
        store.updateSwitches(id: current.id, isEnabled: false, showsInMenuBar: false)
        #expect(!store.canDeliver(event, for: current))
        store.remove(id: current.id)
        #expect(!store.canDeliver(event, for: current))
    }

    @Test func cloneDisablesAlertsAndRuleParticipatesInDraftButNotConnectionTest() {
        let monitor = monitor()
        let clone = makeMonitorClone(from: monitor, name: "Copy", order: 1)
        #expect(!clone.alertRule.isEnabled)
        #expect(!clone.runtime.alertState.isActive)
        var changed = monitor
        changed.alertRule.threshold = 20
        #expect(EditorEditableConfiguration(monitor: monitor) != EditorEditableConfiguration(monitor: changed))
        #expect(EditorTestConfiguration(monitor: monitor) == EditorTestConfiguration(monitor: changed))
    }

    @Test func notificationBodyNeverIncludesRequestSecretsOrRemoteErrors() {
        var monitor = monitor()
        monitor.urlString = "https://example.com/private?token=secret"
        monitor.runtime.lastError = .request("remote secret response")
        let event = MonitorAlertEvent(kind: .abnormal, incidentID: UUID(), value: nil)
        let body = MonitorNotificationService.body(for: event, monitor: monitor)
        #expect(!body.contains("secret"))
        #expect(!body.contains("example.com"))
    }

    @Test func notificationDedupeIsDurableBeforeDeliveryAndSurvivesRestart() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = PersistenceController(directoryURL: directory)
        let monitor = monitor()
        try persistence.save(monitors: [monitor])
        let store = MonitorStore(persistence: persistence)
        store.notificationPermission = .authorized
        var delivered = false
        store.onAlert = { _, event in
            #expect(persistence.load().state.monitors.first?.runtime.alertState.incidentID == event.incidentID)
            #expect(persistence.load().state.monitors.first?.runtime.alertState.didNotify == true)
            delivered = true
        }
        for _ in 0..<3 {
            store.record(requestedMonitor: monitor, result: .failure(.requestTimedOut), at: Date(), response: nil)
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !delivered, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        #expect(delivered)
        await store.flushPersistence()
        let restarted = MonitorStore(persistence: persistence)
        restarted.notificationPermission = .authorized
        restarted.onAlert = { _, _ in Issue.record("Restart repeated an active incident notification") }
        for _ in 0..<4 {
            restarted.record(requestedMonitor: monitor, result: .failure(.requestTimedOut), at: Date(), response: nil)
        }
        await restarted.flushPersistence()
        #expect(restarted.monitor(id: monitor.id)?.runtime.alertState.didNotify == true)
    }

    @Test func clockPublishesOnlyWhenFreshnessChanges() {
        let date = Date()
        let monitor = Monitor(name: "Clock", runtime: .init(lastValue: 1, lastSuccessAt: date))
        let store = MonitorStore(initialMonitors: [monitor])
        let previous = store.now
        store.tick(at: date.addingTimeInterval(10))
        #expect(store.now == previous)
        store.tick(at: date.addingTimeInterval(monitor.staleAfter + 1))
        #expect(store.health(for: monitor).isStale)
    }
}
