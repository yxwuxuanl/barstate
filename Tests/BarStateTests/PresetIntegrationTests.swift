import BarStateCore
import Foundation
import Testing
@testable import BarState

struct PresetIntegrationTests {
    @Test func apiClientParsesPresetWithoutUserExpression() async {
        let client = APIClient()
        let monitor = Monitor(
            name: "Router", preset: DataSourcePreset(provider: .openRouter),
            parser: ParserConfiguration(jsonPath: "$.not.the.metric")
        )
        let response = HTTPResponseSnapshot(
            requestedAt: Date(), bodyText: #"{"data":{"usage_daily":1.25}}"#, bodyKind: .json
        )
        let value = await client.parseValue(from: response, for: monitor)
        #expect(value == .success(1.25))
    }

    @Test @MainActor func switchingMetricClearsOldValueAndRejectsQueuedResult() throws {
        let old = Monitor(
            name: "Router", preset: DataSourcePreset(provider: .openRouter),
            runtime: MonitorRuntimeState(lastValue: 45, lastSuccessAt: Date())
        )
        let store = MonitorStore(initialMonitors: [old])
        var changed = old
        changed.preset?.metric = .remainingBudget
        store.update(changed)
        #expect(store.monitor(id: old.id)?.runtime.lastValue == nil)
        store.record(requestedMonitor: old, result: .success(999), at: Date(), response: nil)
        #expect(store.monitor(id: old.id)?.runtime.lastValue == nil)
        store.record(requestedMonitor: changed, result: .success(2), at: Date(), response: nil)
        #expect(store.monitor(id: old.id)?.runtime.lastValue == 2)
    }

    @Test @MainActor func displayEditsKeepLatestSuccessfulValue() {
        let old = Monitor(name: "Quota", runtime: MonitorRuntimeState(lastValue: 15, lastSuccessAt: Date()))
        let store = MonitorStore(initialMonitors: [old])
        var changed = old
        changed.displayTemplate = "${value}%"
        store.update(changed)
        #expect(store.monitor(id: old.id)?.runtime.lastValue == 15)
    }

    @Test func presetChangesInvalidateEditorTestAndDraftIdentity() {
        let old = Monitor(name: "Router", preset: DataSourcePreset(provider: .openRouter, apiKey: "old-key"))
        var changed = old
        changed.preset?.apiKey = "new-key"
        #expect(EditorTestConfiguration(monitor: old) != EditorTestConfiguration(monitor: changed))
        #expect(EditorEditableConfiguration(monitor: old) != EditorEditableConfiguration(monitor: changed))
        changed = old
        changed.preset?.metric = .usageMonthly
        #expect(EditorTestConfiguration(monitor: old) != EditorTestConfiguration(monitor: changed))
    }
}
