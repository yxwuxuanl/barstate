import Foundation
import Testing
@testable import BarStateCore

struct DataSourcePresetTests {
    @Test func deepSeekSelectsCurrencyRatherThanArrayPosition() throws {
        let data = Data(#"{"is_available":true,"balance_infos":[{"currency":"USD","total_balance":"50"},{"currency":"CNY","total_balance":"12.34"}]}"#.utf8)
        var preset = DataSourcePreset(provider: .deepSeek)
        #expect(try preset.number(from: data) == 12.34)
        preset.currency = .usd
        #expect(try preset.number(from: data) == 50)
        #expect(preset.unit == "USD")
    }

    @Test func missingOrAmbiguousCurrencyIsNotZero() {
        let preset = DataSourcePreset(provider: .deepSeek)
        let data = Data(#"{"balance_infos":[{"currency":"USD","total_balance":"10"}]}"#.utf8)
        #expect(throws: MonitoringError.presetCurrencyUnavailable) { try preset.number(from: data) }
        let duplicate = Data(#"{"balance_infos":[{"currency":"CNY","total_balance":"1"},{"currency":"CNY","total_balance":"2"}]}"#.utf8)
        #expect(throws: MonitoringError.presetCurrencyUnavailable) { try preset.number(from: duplicate) }
    }

    @Test func zeroAndNegativeBalancesRemainValid() throws {
        let preset = DataSourcePreset(provider: .deepSeek)
        #expect(try preset.number(from: Data(#"{"is_available":false,"balance_infos":[{"currency":"CNY","total_balance":"0"}]}"#.utf8)) == 0)
        #expect(try preset.number(from: Data(#"{"balance_infos":[{"currency":"CNY","total_balance":-2.5}]}"#.utf8)) == -2.5)
    }

    @Test func openRouterSeparatesUsageAndBudget() throws {
        let data = Data(#"{"data":{"usage_daily":1.25,"usage_monthly":12.5,"limit":20,"limit_remaining":7.5}}"#.utf8)
        var preset = DataSourcePreset(provider: .openRouter)
        #expect(try preset.number(from: data) == 1.25)
        preset.metric = .usageMonthly
        #expect(try preset.number(from: data) == 12.5)
        preset.metric = .remainingBudget
        #expect(try preset.number(from: data) == 7.5)
    }

    @Test func unlimitedBudgetAndExhaustedBudgetAreDifferent() throws {
        var preset = DataSourcePreset(provider: .openRouter, metric: .remainingBudget)
        let unlimited = Data(#"{"data":{"limit":null,"limit_remaining":null,"usage_daily":0}}"#.utf8)
        #expect(throws: MonitoringError.presetBudgetUnset) { try preset.number(from: unlimited) }
        let exhausted = Data(#"{"data":{"limit":10,"limit_remaining":0}}"#.utf8)
        #expect(try preset.number(from: exhausted) == 0)
        preset.metric = .usageDaily
        #expect(try preset.number(from: unlimited) == 0)
    }

    @Test func siliconFlowUsesTotalBalanceAndChecksBusinessStatus() throws {
        let preset = DataSourcePreset(provider: .siliconFlow)
        let data = Data(#"{"code":20000,"status":true,"data":{"balance":"0.88","chargeBalance":"88","totalBalance":"88.88"}}"#.utf8)
        #expect(try preset.number(from: data) == 88.88)
        #expect(preset.unit == "CNY")
        let rejected = Data(#"{"code":50000,"status":false,"data":{"totalBalance":"88.88"}}"#.utf8)
        #expect(throws: MonitoringError.presetServiceRejected) { try preset.number(from: rejected) }
    }

    @Test(arguments: ["true", "\"bad-number\"", "{}", "[]"])
    func rejectsNonNumericValues(value: String) {
        let preset = DataSourcePreset(provider: .openRouter)
        let data = Data("{\"data\":{\"usage_daily\":\(value)}}".utf8)
        #expect(throws: MonitoringError.presetInvalidData) { try preset.number(from: data) }
    }

    @Test(arguments: ["NaN", "Infinity", "-Infinity"])
    func rejectsNonFiniteValues(value: String) {
        let preset = DataSourcePreset(provider: .openRouter)
        let data = Data("{\"data\":{\"usage_daily\":\"\(value)\"}}".utf8)
        #expect(throws: MonitoringError.nonFiniteNumber) { try preset.number(from: data) }
    }

    @Test func missingMetricIsNotZero() {
        let preset = DataSourcePreset(provider: .openRouter)
        #expect(throws: MonitoringError.presetValueMissing) {
            try preset.number(from: Data(#"{"data":{}}"#.utf8))
        }
    }

    @Test func requestUsesPresetEndpointAndDedicatedKey() throws {
        let monitor = Monitor(
            name: "Balance", preset: DataSourcePreset(provider: .siliconFlow, apiKey: " test-key "),
            urlString: "https://ignored.example.com",
            authentication: HTTPAuthentication(kind: .basic, username: "unused", password: "unused"),
            requestTimeout: 23
        )
        let request = try HTTPRequestBuilder.makeRequest(for: monitor)
        #expect(request.url?.absoluteString == "https://api.siliconflow.cn/v1/user/info")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
        #expect(request.httpMethod == "GET")
        #expect(request.timeoutInterval == 23)
    }

    @Test func invalidCredentialsCannotFormARequest() {
        #expect(throws: MonitoringError.presetKeyRequired) {
            try DataSourcePreset(provider: .deepSeek).makeRequest(timeout: 10)
        }
        #expect(throws: MonitoringError.presetKeyInvalid) {
            try DataSourcePreset(provider: .deepSeek, apiKey: "key\r\nOther: value").makeRequest(timeout: 10)
        }
    }

    @Test func sanitizedResponseRetainsMetricsAndRemovesAccountFields() throws {
        let preset = DataSourcePreset(provider: .siliconFlow)
        let data = Data(#"{"code":20000,"status":true,"message":"private error","data":{"email":"private@example.com","id":"account-id","totalBalance":"10.5"}}"#.utf8)
        let sanitized = preset.sanitizedSnapshotData(from: data)
        #expect(try preset.number(from: sanitized) == 10.5)
        let text = String(decoding: sanitized, as: UTF8.self)
        #expect(!text.contains("private"))
        #expect(!text.contains("account-id"))
    }

    @Test func legacyHTTPIsNotAutomaticallyConvertedToPreset() throws {
        let monitor = Monitor(name: "Legacy", urlString: DataSourceProvider.deepSeek.endpoint)
        let data = try JSONEncoder().encode(monitor)
        let decoded = try JSONDecoder().decode(Monitor.self, from: data)
        #expect(decoded.preset == nil)
        #expect(decoded.prometheusTemplate == nil)
        #expect(decoded.sourceKind == .httpAPI)
    }

    @Test func presetIdentityAndMetricRoundTrip() throws {
        let monitor = Monitor(name: "Router", preset: DataSourcePreset(
            provider: .openRouter, metric: .remainingBudget, apiKey: "fixture-only"
        ))
        let decoded = try JSONDecoder().decode(Monitor.self, from: JSONEncoder().encode(monitor))
        #expect(decoded == monitor)
        var changed = decoded
        changed.preset?.metric = .usageDaily
        #expect(!monitor.hasSameValueConfiguration(as: changed))
        changed = monitor
        changed.name = "Renamed"
        changed.displayTemplate = "${value} USD"
        #expect(monitor.hasSameValueConfiguration(as: changed))
    }
}
