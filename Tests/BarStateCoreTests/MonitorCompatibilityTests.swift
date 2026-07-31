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

    @Test func statusIndicatorUsesTheHighestReachedValue() {
        let configuration = StatusIndicatorConfiguration(
            isEnabled: true,
            rules: [
                StatusIndicatorRule(value: 90, color: .red),
                StatusIndicatorRule(value: 0, color: .green),
                StatusIndicatorRule(value: 70, color: .orange)
            ]
        )

        #expect(configuration.appearance(for: -1)?.kind == .unavailable)
        #expect(configuration.appearance(for: -1)?.color == .gray)
        #expect(configuration.appearance(for: 0)?.color == .green)
        #expect(configuration.appearance(for: 69.9)?.color == .green)
        #expect(configuration.appearance(for: 70)?.color == .orange)
        #expect(configuration.appearance(for: 89.9)?.color == .orange)
        #expect(configuration.appearance(for: 90)?.color == .red)
        #expect(configuration.appearance(for: 120)?.color == .red)
        #expect(configuration.appearance(for: 85)?.kind == .matched)
    }

    @Test func statusIndicatorHandlesDisabledUnmatchedAndDuplicateRules() {
        let disabled = StatusIndicatorConfiguration()
        #expect(disabled.appearance(for: 1) == nil)

        let enabled = StatusIndicatorConfiguration(
            isEnabled: true,
            rules: [StatusIndicatorRule(value: 1, color: .blue)]
        )
        #expect(enabled.appearance(for: nil)?.kind == .unavailable)
        #expect(enabled.appearance(for: 0)?.kind == .unavailable)
        #expect(enabled.appearance(for: 0)?.color == .gray)
        #expect(enabled.appearance(for: 2)?.color == .blue)

        let invalid = StatusIndicatorConfiguration(
            isEnabled: true,
            rules: [
                StatusIndicatorRule(value: 1, color: .green),
                StatusIndicatorRule(value: 1, color: .red)
            ]
        )
        #expect(!invalid.hasValidRules)
        #expect(invalid.appearance(for: 1)?.kind == .unavailable)
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

    @Test func defaultsLegacyMonitorToDisabledStatusIndicator() throws {
        let monitor = Monitor(
            name: "legacy",
            statusIndicator: StatusIndicatorConfiguration(isEnabled: true)
        )
        let encoded = try JSONEncoder().encode(monitor)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "statusIndicator")

        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(Monitor.self, from: legacyData)

        #expect(decoded.statusIndicator == StatusIndicatorConfiguration())
        #expect(decoded.statusIndicatorAppearance == nil)
    }

    @Test func migratesPreviouslySavedThresholdsToMinimumValueRules() throws {
        let monitor = Monitor(name: "legacy indicator")
        let encoded = try JSONEncoder().encode(monitor)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["statusIndicator"] = [
            "isEnabled": true,
            "direction": "higherIsWorse",
            "warningThreshold": 60,
            "criticalThreshold": 80,
            "normalColor": "blue",
            "warningColor": "purple",
            "criticalColor": "pink"
        ]

        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(Monitor.self, from: legacyData)

        #expect(decoded.statusIndicator.isEnabled)
        #expect(decoded.statusIndicator.rules.map(\.value) == [60, 80])
        #expect(decoded.statusIndicator.rules.map(\.color) == [.purple, .pink])
    }

    @Test func roundTripsCustomValueColorRules() throws {
        let monitor = Monitor(
            name: "custom mappings",
            statusIndicator: StatusIndicatorConfiguration(
                isEnabled: true,
                rules: [
                    StatusIndicatorRule(value: -1, color: .mint),
                    StatusIndicatorRule(value: 3.14, color: .purple)
                ]
            )
        )

        let decoded = try JSONDecoder().decode(
            Monitor.self,
            from: JSONEncoder().encode(monitor)
        )

        #expect(decoded.statusIndicator == monitor.statusIndicator)
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

    @Test func decodesLegacyMonitorAsHTTPAPI() throws {
        let monitor = Monitor(name: "legacy")
        let encoded = try JSONEncoder().encode(monitor)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "sourceKind")
        object.removeValue(forKey: "promQL")

        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(Monitor.self, from: legacyData)

        #expect(decoded.sourceKind == .httpAPI)
        #expect(decoded.promQL.isEmpty)
    }

    @Test func defaultsLegacyMonitorRequestTimeoutToTenSeconds() throws {
        let monitor = Monitor(name: "legacy", requestTimeout: 24)
        let encoded = try JSONEncoder().encode(monitor)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "requestTimeout")

        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(Monitor.self, from: legacyData)

        #expect(decoded.requestTimeout == Monitor.defaultRequestTimeout)
    }

    @Test func defaultsLegacyMonitorAuthenticationToNone() throws {
        let monitor = Monitor(
            name: "legacy",
            authentication: HTTPAuthentication(
                kind: .basic,
                username: "user",
                password: "secret"
            )
        )
        let encoded = try JSONEncoder().encode(monitor)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "authentication")

        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(Monitor.self, from: legacyData)

        #expect(decoded.authentication == HTTPAuthentication())
    }

    @Test func roundTripsBasicAuthenticationConfiguration() throws {
        let monitor = Monitor(
            name: "Basic Auth",
            authentication: HTTPAuthentication(
                kind: .basic,
                username: "用户",
                password: "密碼:secret"
            )
        )

        let data = try JSONEncoder().encode(monitor)
        let decoded = try JSONDecoder().decode(Monitor.self, from: data)

        #expect(decoded.authentication == monitor.authentication)
    }
}
