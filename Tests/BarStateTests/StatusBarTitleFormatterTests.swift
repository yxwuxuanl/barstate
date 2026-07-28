import BarStateCore
import Foundation
import Testing
@testable import BarState

struct StatusBarTitleFormatterTests {
    @Test func truncatesLongTitlesWithinTheConfiguredBudget() {
        let monitor = Monitor(
            name: "long",
            displayTemplate: "A very long metric ${value}",
            runtime: MonitorRuntimeState(lastValue: 42)
        )

        let title = StatusBarTitleFormatter.individualTitle(
            for: monitor,
            maximumCharacters: 12
        )

        #expect(title.count == 12)
        #expect(title.hasSuffix("…"))
    }

    @Test func compactTitlePrioritizesRepeatedFailures() {
        let healthy = Monitor(name: "healthy")
        let recentFailure = Monitor(
            name: "recent",
            runtime: MonitorRuntimeState(consecutiveFailures: 1)
        )
        let repeatedFailure = Monitor(
            name: "repeated",
            runtime: MonitorRuntimeState(consecutiveFailures: 3)
        )

        #expect(
            StatusBarTitleFormatter.compactTitle(
                for: [healthy, recentFailure, repeatedFailure]
            ) == "BarState · 1×"
        )
    }
}
