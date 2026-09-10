import Foundation
import Testing
@testable import BarStateCore

struct MonitorAlertTests {
    let start = Date(timeIntervalSince1970: 1_000)
    let rule = MonitorAlertRule(isEnabled: true, threshold: 20, notifiesRecovery: true)

    @Test func valueIncidentRecoveryAndCooldown() throws {
        var state = MonitorAlertState()
        #expect(state.evaluate(.success(21), rule: rule, at: start) == nil)
        #expect(state.evaluate(.success(19), rule: rule, at: start) == nil)
        let firstEvent = state.evaluate(.success(18), rule: rule, at: start)
        let event = try #require(firstEvent)
        #expect(event.kind == .abnormal)
        #expect(state.isActive)
        #expect(state.evaluate(.success(17), rule: rule, at: start.addingTimeInterval(1000)) == nil)
        #expect(state.evaluate(.success(21), rule: rule, at: start.addingTimeInterval(10)) == nil)
        #expect(state.evaluate(.success(22), rule: rule, at: start.addingTimeInterval(20))?.kind == .recovered)
        #expect(!state.isActive)
        #expect(!state.contains(event))
        #expect(state.evaluate(.success(19), rule: rule, at: start.addingTimeInterval(30)) == nil)
        #expect(state.evaluate(.success(18), rule: rule, at: start.addingTimeInterval(40)) == nil)
        #expect(state.isActive)
        #expect(!state.didNotify)
        let secondEvent = state.evaluate(.success(18), rule: rule, at: start.addingTimeInterval(900))
        let second = try #require(secondEvent)
        #expect(second.incidentID != event.incidentID)
    }

    @Test func failuresInterruptNumericObservationsAndRecovery() {
        var state = MonitorAlertState()
        #expect(state.evaluate(.success(0), rule: rule, at: start) == nil)
        #expect(state.evaluate(.failure(.requestTimedOut), rule: rule, at: start) == nil)
        #expect(state.evaluate(.success(-1), rule: rule, at: start) == nil)
        #expect(state.evaluate(.success(0), rule: rule, at: start)?.kind == .abnormal)
        #expect(state.evaluate(.success(30), rule: rule, at: start) == nil)
        #expect(state.evaluate(.failure(.presetValueMissing), rule: rule, at: start) == nil)
        #expect(state.evaluate(.success(30), rule: rule, at: start) == nil)
        #expect(state.isActive)
        #expect(state.evaluate(.success(30), rule: rule, at: start)?.kind == .recovered)
    }

    @Test func thirdFailureAndSuccessfulZeroRecovery() {
        var state = MonitorAlertState()
        let rule = MonitorAlertRule(isEnabled: true, condition: .requestFailure, notifiesRecovery: true)
        for _ in 0..<2 { #expect(state.evaluate(.failure(.requestTimedOut), rule: rule, at: start) == nil) }
        #expect(state.evaluate(.failure(.requestTimedOut), rule: rule, at: start)?.kind == .abnormal)
        #expect(state.evaluate(.failure(.httpStatus(500)), rule: rule, at: start) == nil)
        #expect(state.evaluate(.success(0), rule: rule, at: start)?.kind == .recovered)
        #expect(!state.isActive)
    }

    @Test func permissionDeniedRetainsIncidentWithoutConsumingNotification() {
        var state = MonitorAlertState()
        for _ in 0..<3 {
            #expect(state.evaluate(.success(10), rule: rule, at: start, allowsNotification: false) == nil)
        }
        #expect(state.isActive)
        #expect(!state.didNotify)
        #expect(state.evaluate(.success(10), rule: rule, at: start)?.kind == .abnormal)
    }

    @Test func restartDeduplicatesAndEditsResetObservations() throws {
        var state = MonitorAlertState()
        _ = state.evaluate(.success(10), rule: rule, at: start)
        _ = state.evaluate(.success(10), rule: rule, at: start)
        let data = try JSONEncoder().encode(state)
        state = try JSONDecoder().decode(MonitorAlertState.self, from: data)
        state.interruptSamples()
        for _ in 0..<3 { #expect(state.evaluate(.success(10), rule: rule, at: start.addingTimeInterval(3600)) == nil) }
        state.reset()
        #expect(!state.isActive)
        #expect(state.lastNotifiedAt == start)
        #expect(state.evaluate(.success(10), rule: rule, at: start.addingTimeInterval(3600)) == nil)
        #expect(state.evaluate(.success(10), rule: rule, at: start.addingTimeInterval(3600)) != nil)
    }

    @Test func disabledRuleNeverNotifies() {
        var state = MonitorAlertState()
        for _ in 0..<4 { #expect(state.evaluate(.success(0), rule: .init(), at: start) == nil) }
        #expect(!state.isActive)
    }
}
