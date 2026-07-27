import BarStateCore
import Foundation
import Testing
@testable import BarState

struct PollingEngineTests {
    @Test func staleRequestCannotOverwriteChangedConfiguration() async {
        let fetcher = TestValueFetcher(delays: ["old": .milliseconds(250), "new": .milliseconds(20)])
        let results = ResultRecorder()
        let id = UUID()
        let engine = PollingEngine(
            valueFetcher: fetcher,
            maximumConcurrentRequests: 1,
            resultHandler: { _, outcome, _ in
                await results.append(outcome)
            }
        )

        var oldMonitor = Monitor(id: id, name: "test", urlString: "https://example.com/old")
        oldMonitor.label = "old"
        await engine.update(monitors: [oldMonitor])
        try? await Task.sleep(for: .milliseconds(20))

        var newMonitor = oldMonitor
        newMonitor.urlString = "https://example.com/new"
        newMonitor.label = "new"
        await engine.update(monitors: [newMonitor])

        let receivedNewResult = await waitUntil { await results.count == 1 }
        let values = await results.values
        #expect(receivedNewResult)
        #expect(values == [2])
        await engine.stop()
    }

    @Test func limitsConcurrentRequestsAndDrainsStartupQueue() async {
        let fetcher = TestValueFetcher(defaultDelay: .milliseconds(40))
        let results = ResultRecorder()
        let engine = PollingEngine(
            valueFetcher: fetcher,
            maximumConcurrentRequests: 2,
            resultHandler: { _, outcome, _ in
                await results.append(outcome)
            }
        )
        let monitors = (0..<8).map {
            Monitor(name: "monitor-\($0)", urlString: "https://example.com/\($0)", order: $0)
        }

        await engine.update(monitors: monitors)

        let drainedQueue = await waitUntil(timeout: .seconds(2)) {
            await results.count == monitors.count
        }
        let maximumConcurrency = await fetcher.maximumObservedConcurrency
        #expect(drainedQueue)
        #expect(maximumConcurrency <= 2)
        await engine.stop()
    }

    @Test func staleRequestCannotOverwriteChangedPromQL() async {
        let fetcher = TestValueFetcher(delays: [
            "old-query": .milliseconds(250),
            "new-query": .milliseconds(20)
        ])
        let results = ResultRecorder()
        let id = UUID()
        let engine = PollingEngine(
            valueFetcher: fetcher,
            maximumConcurrentRequests: 1,
            resultHandler: { _, outcome, _ in
                await results.append(outcome)
            }
        )

        let oldMonitor = Monitor(
            id: id,
            name: "Prometheus",
            sourceKind: .prometheus,
            urlString: "https://metrics.example.com",
            promQL: "old-query"
        )
        await engine.update(monitors: [oldMonitor])
        try? await Task.sleep(for: .milliseconds(20))

        var newMonitor = oldMonitor
        newMonitor.promQL = "new-query"
        await engine.update(monitors: [newMonitor])

        let receivedNewResult = await waitUntil { await results.count == 1 }
        let values = await results.values
        #expect(receivedNewResult)
        #expect(values == [2])
        await engine.stop()
    }

    @Test func refreshRequestedWhileRunningIsQueued() async {
        let fetcher = TestValueFetcher(defaultDelay: .milliseconds(80))
        let results = ResultRecorder()
        let engine = PollingEngine(
            valueFetcher: fetcher,
            maximumConcurrentRequests: 1,
            resultHandler: { _, outcome, _ in
                await results.append(outcome)
            }
        )
        let monitor = Monitor(name: "queued", urlString: "https://example.com/value")

        await engine.update(monitors: [monitor])
        try? await Task.sleep(for: .milliseconds(15))
        await engine.refreshAll()

        let receivedBothResults = await waitUntil { await results.count == 2 }
        #expect(receivedBothResults)
        await engine.stop()
    }
}

private actor TestValueFetcher: MonitorValueFetching {
    private let delays: [String: Duration]
    private let defaultDelay: Duration
    private var activeCount = 0
    private(set) var maximumObservedConcurrency = 0

    init(delays: [String: Duration] = [:], defaultDelay: Duration = .milliseconds(30)) {
        self.delays = delays
        self.defaultDelay = defaultDelay
    }

    func fetchValue(for monitor: Monitor) async -> FetchOutcome {
        activeCount += 1
        maximumObservedConcurrency = max(maximumObservedConcurrency, activeCount)
        let key = monitor.sourceKind == .prometheus
            ? monitor.promQL
            : monitor.urlString.components(separatedBy: "/").last ?? ""
        do {
            try await Task.sleep(for: delays[key] ?? defaultDelay)
        } catch {
            // Returning after cancellation exercises the engine's generation guard.
        }
        activeCount -= 1

        let value = key.hasPrefix("old") ? 1.0 : 2.0
        return FetchOutcome(
            formattedResponse: "{\"value\":\(value)}",
            requestedAt: Date(),
            result: .success(value)
        )
    }
}

private actor ResultRecorder {
    private var outcomes: [FetchOutcome] = []

    func append(_ outcome: FetchOutcome) {
        outcomes.append(outcome)
    }

    var count: Int { outcomes.count }

    var values: [Double] {
        outcomes.compactMap { try? $0.result.get() }
    }
}

private func waitUntil(
    timeout: Duration = .seconds(1),
    condition: @escaping @Sendable () async -> Bool
) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return await condition()
}
