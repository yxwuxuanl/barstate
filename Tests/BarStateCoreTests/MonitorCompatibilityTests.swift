import Foundation
import Testing
@testable import BarStateCore

struct MonitorCompatibilityTests {
    @Test func rendersTheDisplayTemplate() {
        let monitor = Monitor(
            name: "气温",
            displayTemplate: "气温${value}℃",
            runtime: MonitorRuntimeState(lastValue: 30.1)
        )

        #expect(monitor.displayText == "气温30.1℃")
        #expect(monitor.menuBarTitle == "气温30.1℃")
    }

    @Test func migratesLegacyLabelAndUnitToDisplayTemplate() throws {
        let monitor = Monitor(name: "气温", label: "气温 ", unit: "℃")
        let encoded = try JSONEncoder().encode(monitor)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "displayTemplate")
        object["label"] = "气温 "
        object["unit"] = "℃"

        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(Monitor.self, from: legacyData)

        #expect(decoded.displayTemplate == "气温 ${value}℃")
    }

    @Test func migratesLegacyResponseBodyAndRequestTime() throws {
        let monitor = Monitor(name: "旧监控项")
        let encoded = try JSONEncoder().encode(monitor)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var runtime = try #require(object["runtime"] as? [String: Any])
        runtime.removeValue(forKey: "lastResponse")
        runtime["lastResponseText"] = #"{"value":30}"#
        runtime["lastResponseAt"] = 1_000
        object["runtime"] = runtime

        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let decoded = try decoder.decode(Monitor.self, from: legacyData)

        #expect(decoded.runtime.lastResponse?.bodyText == #"{"value":30}"#)
        #expect(decoded.runtime.lastResponse?.bodyKind == .json)
        #expect(decoded.runtime.lastResponse?.requestedAt == Date(timeIntervalSince1970: 1_000))
    }

    @Test func migratesLegacyLocalizedErrorString() throws {
        let monitor = Monitor(name: "legacy")
        let encoded = try JSONEncoder().encode(monitor)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var runtime = try #require(object["runtime"] as? [String: Any])
        runtime["lastError"] = "legacy failure"
        object["runtime"] = runtime

        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(Monitor.self, from: legacyData)

        #expect(decoded.runtime.lastError == .legacy("legacy failure"))
    }
}
