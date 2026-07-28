import Foundation

struct FirstLaunchSettingsPolicy {
    private static let hasShownSettingsKey = "firstLaunch.hasShownSettings.v1"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func consumeShouldShowSettings() -> Bool {
        guard !defaults.bool(forKey: Self.hasShownSettingsKey) else { return false }
        defaults.set(true, forKey: Self.hasShownSettingsKey)
        return true
    }
}
