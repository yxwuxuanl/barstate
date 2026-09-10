import BarStateCore
import Foundation
import Testing
@testable import BarState

struct InFlightRequestsTests {
    @Test func sharesOnlyInFlightWorkAndKeepsCancellationIndependent() async throws {
        let requests = InFlightRequests<String, Int>()
        let probe = RequestProbe()
        let first = Task { try await requests.value(for: "account") { try await probe.run() } }
        let second = Task { try await requests.value(for: "account") { try await probe.run() } }
        try await eventually { await requests.waitingCount == 2 }
        #expect(await probe.calls == 1)
        first.cancel()
        do { _ = try await first.value; Issue.record("Cancelled subscriber received a value") }
        catch is CancellationError {} catch { Issue.record("Unexpected cancellation error") }
        #expect(await probe.cancellations == 0)
        await probe.finish(7)
        #expect(try await second.value == 7)
        #expect(await requests.waitingCount == 0)
        #expect(try await requests.value(for: "account") { 9 } == 9)
    }

    @Test func lastSubscriberCancellationStopsWorkAndNewRequestIsIndependent() async throws {
        let requests = InFlightRequests<String, Int>()
        let probe = RequestProbe()
        let first = Task { try await requests.value(for: "account") { try await probe.run() } }
        try await eventually { await probe.calls == 1 }
        first.cancel()
        _ = try? await first.value
        try await eventually { await probe.cancellations == 1 }
        #expect(await requests.waitingCount == 0)
        #expect(try await requests.value(for: "account") { 42 } == 42)
    }

    @Test func differentAccountsAndDeadlinesDoNotShare() throws {
        let first = Monitor(name: "A", preset: DataSourcePreset(provider: .openRouter, apiKey: "key-a"))
        var second = first
        second.preset?.metric = .usageMonthly
        let identity = HTTPRequestIdentity(try HTTPRequestBuilder.makeRequest(for: first))
        #expect(identity == HTTPRequestIdentity(try HTTPRequestBuilder.makeRequest(for: second)))
        second.preset?.apiKey = "key-b"
        #expect(identity != HTTPRequestIdentity(try HTTPRequestBuilder.makeRequest(for: second)))
        second = first
        second.requestTimeout = 30
        #expect(identity != HTTPRequestIdentity(try HTTPRequestBuilder.makeRequest(for: second)))
    }
}

private actor RequestProbe {
    private(set) var calls = 0
    private(set) var cancellations = 0
    private var continuation: CheckedContinuation<Int, any Error>?

    func run() async throws -> Int {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                calls += 1
                self.continuation = continuation
            }
        } onCancel: { Task { await self.cancel() } }
    }

    func finish(_ value: Int) {
        continuation?.resume(returning: value)
        continuation = nil
    }

    private func cancel() {
        cancellations += 1
        continuation?.resume(throwing: CancellationError())
        continuation = nil
    }
}

private func eventually(_ condition: @escaping @Sendable () async -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while !(await condition()) {
        if ContinuousClock.now >= deadline { throw ProbeTimeout() }
        try await Task.sleep(for: .milliseconds(5))
    }
}
private struct ProbeTimeout: Error {}
