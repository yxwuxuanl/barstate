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

    @Test func compactIndicatorShowsSharedColorAndMarksMixedColors() {
        let blue = Monitor(
            name: "blue",
            statusIndicator: StatusIndicatorConfiguration(
                isEnabled: true,
                rules: [StatusIndicatorRule(value: 1, color: .blue)]
            ),
            runtime: MonitorRuntimeState(lastValue: 1)
        )
        let anotherBlue = Monitor(
            name: "another blue",
            statusIndicator: StatusIndicatorConfiguration(
                isEnabled: true,
                rules: [StatusIndicatorRule(value: 2, color: .blue)]
            ),
            runtime: MonitorRuntimeState(lastValue: 2)
        )
        let red = Monitor(
            name: "red",
            statusIndicator: StatusIndicatorConfiguration(
                isEnabled: true,
                rules: [StatusIndicatorRule(value: 3, color: .red)]
            ),
            runtime: MonitorRuntimeState(lastValue: 3)
        )

        let shared = StatusBarTitleFormatter.compactIndicatorAppearance(
            for: [blue, anotherBlue]
        )
        #expect(shared?.kind == .matched)
        #expect(shared?.color == .blue)

        let mixed = StatusBarTitleFormatter.compactIndicatorAppearance(
            for: [blue, red]
        )
        #expect(mixed?.kind == .mixed)
        #expect(mixed?.color == .gray)
    }
}
