import Foundation
import Testing
@testable import BarStateCore

struct LocalizationTests {
    @Test func resolvesRepresentativeResourceKeys() {
        for key in [
            "common.save",
            "popover.refresh_all",
            "editor.validation.valid_https_url",
            "error.script_timeout"
        ] {
            #expect(L10n.string(key) != key)
        }
    }

    @Test func resolvesPluralFormats() {
        for count in [1, 2] {
            let value = L10n.plural("popover.refreshing_count", count: count)
            #expect(value.contains(String(count)))
            #expect(!value.contains("%#@"))
        }
    }

    @Test func structuredErrorSurvivesPersistence() throws {
        let runtime = MonitorRuntimeState(lastError: .request("offline"))
        let data = try JSONEncoder().encode(runtime)
        let decoded = try JSONDecoder().decode(MonitorRuntimeState.self, from: data)

        #expect(decoded.lastError == .request("offline"))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["lastFailure"] != nil)
        #expect(object["lastError"] == nil)
    }
}
