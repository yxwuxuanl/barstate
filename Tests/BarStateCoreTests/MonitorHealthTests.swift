import Foundation
import Testing
@testable import BarStateCore

struct MonitorHealthTests {
    let start = Date(timeIntervalSince1970: 1_000)

    @Test(arguments: [30.0, 300.0, 86_400.0]) func staleBoundaryAndClockCorrections(interval: Double) {
        let monitor = Monitor(name: "Health", refreshInterval: interval,
                              runtime: .init(lastValue: 1, lastSuccessAt: start))
        #expect(MonitorHealth(monitor: monitor, now: start.addingTimeInterval(monitor.staleAfter)).phase == .healthy)
        let stale = MonitorHealth(monitor: monitor, now: start.addingTimeInterval(monitor.staleAfter + 1))
        #expect(stale.phase == .stale)
        #expect(stale.showsPreviousValue)
        #expect(MonitorHealth(monitor: monitor, now: start.addingTimeInterval(-60)).isStale)
        let refreshing = MonitorHealth(monitor: monitor, now: start.addingTimeInterval(monitor.staleAfter + 1), isRefreshing: true)
        #expect(refreshing.phase == .refreshing)
        #expect(refreshing.isStale)
    }

    @Test func failureValueRetentionAndHealthPriority() {
        var monitor = Monitor(name: "Health")
        #expect(MonitorHealth(monitor: monitor, now: start).phase == .waiting)
        monitor.runtime.recordSuccess(0, at: start)
        for count in 1...3 {
            monitor.runtime.recordFailure(.requestTimedOut, at: start)
            #expect(monitor.runtime.displayValue == (count < 3 ? 0 : nil))
            #expect(MonitorHealth(monitor: monitor, now: start).phase == (count < 3 ? .retrying : .failed))
            #expect(MonitorHealth(monitor: monitor, now: start).lastSuccessAt == start)
        }
        #expect(MonitorHealth(monitor: monitor, now: start, isNetworkOffline: true).phase == .offline)
        monitor.isEnabled = false
        #expect(MonitorHealth(monitor: monitor, now: start, isRefreshing: true, isNetworkOffline: true).phase == .disabled)
    }

    @Test(arguments: ["http://127.0.0.1:9090", "http://localhost:9090", "http://[::1]:9090"])
    func loopbackPrometheusRemainsAvailableOffline(url: String) {
        let monitor = Monitor(name: "Local", sourceKind: .prometheus, urlString: url)
        #expect(monitor.usesLoopbackConnection)
        #expect(MonitorHealth(monitor: monitor, now: start, isNetworkOffline: true).phase == .waiting)
    }
}
