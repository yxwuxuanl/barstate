import Foundation
import Testing
@testable import BarStateCore

struct MonitorRuntimeStateTests {
    @Test func keepsValueForTwoFailuresThenHidesIt() {
        var state = MonitorRuntimeState()
        let date = Date(timeIntervalSince1970: 1_000)

        state.recordSuccess(30, at: date)
        state.recordFailure(.legacy("一次失败"), at: date)
        #expect(state.displayValue == 30)
        state.recordFailure(.legacy("二次失败"), at: date)
        #expect(state.displayValue == 30)
        state.recordFailure(.legacy("三次失败"), at: date)
        #expect(state.displayValue == nil)
    }

    @Test func successClearsFailureCount() {
        var state = MonitorRuntimeState(consecutiveFailures: 3)
        state.recordSuccess(7.24, at: Date())
        #expect(state.consecutiveFailures == 0)
        #expect(state.displayValue == 7.24)
    }

    @Test func convertsRefreshIntervalUnits() {
        #expect(RefreshIntervalUnit.seconds.seconds(for: 30) == 30)
        #expect(RefreshIntervalUnit.minutes.seconds(for: 2.5) == 150)
        #expect(RefreshIntervalUnit.hours.seconds(for: 1.5) == 5_400)
        #expect(RefreshIntervalUnit.minutes.value(for: 90) == 1.5)
    }

    @Test func keepsLastReceivedResponseWhenARequestHasNoResponse() {
        var state = MonitorRuntimeState()
        let firstRequestAt = Date(timeIntervalSince1970: 1_000)

        state.recordSuccess(
            30,
            at: firstRequestAt.addingTimeInterval(1),
            responseText: #"{"value":30}"#,
            responseAt: firstRequestAt
        )
        state.recordFailure(
            .legacy("请求超时"),
            at: firstRequestAt.addingTimeInterval(60),
            responseText: nil,
            responseAt: firstRequestAt.addingTimeInterval(59)
        )

        #expect(state.lastResponseText == #"{"value":30}"#)
        #expect(state.lastResponseAt == firstRequestAt)
    }

    @Test func newerReceivedResponseReplacesThePreviousResponse() {
        var state = MonitorRuntimeState()
        let requestAt = Date(timeIntervalSince1970: 2_000)

        state.recordFailure(
            .legacy("HTTP 503"),
            at: requestAt.addingTimeInterval(1),
            responseText: #"{"error":"unavailable"}"#,
            responseAt: requestAt
        )

        #expect(state.lastResponseText == #"{"error":"unavailable"}"#)
        #expect(state.lastResponseAt == requestAt)
    }

    @Test func storesTheCompleteHTTPResponseSnapshot() {
        var state = MonitorRuntimeState()
        let requestAt = Date(timeIntervalSince1970: 3_000)
        let response = HTTPResponseSnapshot(
            requestedAt: requestAt,
            statusCode: 200,
            reasonPhrase: "OK",
            httpVersion: "HTTP/2",
            headers: [HTTPResponseHeader(name: "Content-Type", value: "text/plain")],
            bodyText: "30",
            bodyKind: .text
        )

        state.recordSuccess(30, at: requestAt, response: response)

        #expect(state.lastResponse == response)
        #expect(state.lastResponse?.statusLine == "HTTP/2 200 OK")
        #expect(state.lastResponse?.contentType == "text/plain")
    }
}
