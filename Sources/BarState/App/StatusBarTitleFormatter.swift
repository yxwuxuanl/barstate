import BarStateCore
import Foundation

enum StatusBarTitleFormatter {
    static func individualTitle(for monitor: Monitor, maximumCharacters: Int) -> String {
        truncated(monitor.menuBarTitle, maximumCharacters: maximumCharacters)
    }

    static func compactTitle(for monitors: [Monitor]) -> String {
        let repeatedFailures = monitors.filter { $0.runtime.consecutiveFailures >= 3 }.count
        if repeatedFailures > 0 {
            return "BarState · \(repeatedFailures)×"
        }
        let recentFailures = monitors.filter { $0.runtime.consecutiveFailures > 0 }.count
        if recentFailures > 0 {
            return "BarState · \(recentFailures)!"
        }
        return "BarState"
    }

    static func truncated(_ title: String, maximumCharacters: Int) -> String {
        let maximumCharacters = AppPreferences.normalizedMenuBarCharacters(maximumCharacters)
        guard title.count > maximumCharacters else { return title }
        let visibleCount = max(1, maximumCharacters - 1)
        return String(title.prefix(visibleCount)) + "…"
    }
}
