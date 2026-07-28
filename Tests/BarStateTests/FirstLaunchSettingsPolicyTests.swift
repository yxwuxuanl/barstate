import Foundation
import Testing
@testable import BarState

struct FirstLaunchSettingsPolicyTests {
    @Test func settingsAreShownOnlyOnFirstLaunch() throws {
        let suiteName = "FirstLaunchSettingsPolicyTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let policy = FirstLaunchSettingsPolicy(defaults: defaults)

        #expect(policy.consumeShouldShowSettings())
        #expect(!policy.consumeShouldShowSettings())

        let reloadedPolicy = FirstLaunchSettingsPolicy(defaults: defaults)
        #expect(!reloadedPolicy.consumeShouldShowSettings())
    }
}
