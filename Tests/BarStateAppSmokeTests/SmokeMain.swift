import BarStateCore
import Foundation

@main
struct BarStateAppSmokeTests {
    static func main() async throws {
        let presetLanguage = ProcessInfo.processInfo.environment[
            "BARSTATE_PRESET_LANGUAGE"
        ].flatMap(AppLanguage.init(rawValue:))
        presetLanguage?.save()
        defer {
            if presetLanguage != nil {
                AppLanguage.system.save()
            }
        }

        try testResponseAndParserCompatibility()
        try testLocalizationAndErrorPersistence()
        try testPersistenceRecoveryAndPermissions()
        try await testPollingGenerationAndConcurrency()
        testManualRefreshFeedback()
        print("BarState app smoke tests passed")
    }

    private static func testResponseAndParserCompatibility() throws {
        let monitor = Monitor(
            name: "temperature",
            displayTemplate: "气温${value}℃",
            runtime: MonitorRuntimeState(lastValue: 30.1)
        )
        precondition(monitor.displayText == "气温30.1℃", "display template rendering failed")

        let parsed = try JavaScriptEvaluator.evaluate(
            responseData: Data("remaining=30.1".utf8),
            scriptBody: "function(response) { return response.split('=')[1] }"
        )
        precondition(parsed == 30.1, "plain-text JavaScript parsing failed")

        let source = JavaScriptEvaluator.updatingResponseType(
            in: JavaScriptEvaluator.defaultFunctionSource,
            bodyKind: .text
        )
        precondition(source.contains("@param {string} response"), "JSDoc response type was not updated")

        let snapshot = HTTPResponseSnapshot(
            requestedAt: Date(timeIntervalSince1970: 1_000),
            statusCode: 200,
            reasonPhrase: "OK",
            httpVersion: "HTTP/2",
            headers: [HTTPResponseHeader(name: "Content-Type", value: "text/plain")],
            bodyText: "30.1",
            bodyKind: .text
        )
        let decoded = try JSONDecoder().decode(
            HTTPResponseSnapshot.self,
            from: JSONEncoder().encode(snapshot)
        )
        precondition(decoded == snapshot, "HTTP response snapshot persistence failed")

        let legacyMonitor = Monitor(name: "legacy", label: "气温 ", unit: "℃")
        var legacyObject = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(legacyMonitor)
        ) as! [String: Any]
        legacyObject.removeValue(forKey: "displayTemplate")
        legacyObject["label"] = "气温 "
        legacyObject["unit"] = "℃"
        var legacyRuntime = legacyObject["runtime"] as! [String: Any]
        legacyRuntime["lastResponseText"] = #"{"value":30}"#
        legacyRuntime["lastResponseAt"] = 1_000
        legacyRuntime["lastError"] = "legacy failure"
        legacyObject["runtime"] = legacyRuntime

        let legacyDecoder = JSONDecoder()
        legacyDecoder.dateDecodingStrategy = .secondsSince1970
        let migrated = try legacyDecoder.decode(
            Monitor.self,
            from: JSONSerialization.data(withJSONObject: legacyObject)
        )
        precondition(migrated.displayTemplate == "气温 ${value}℃", "display template migration failed")
        precondition(migrated.runtime.lastResponse?.bodyKind == .json, "response migration failed")
        precondition(
            migrated.runtime.lastError == .legacy("legacy failure"),
            "legacy string errors must remain readable"
        )
    }

    private static func testLocalizationAndErrorPersistence() throws {
        if let requestedLanguage = ProcessInfo.processInfo.environment["BARSTATE_LANGUAGE"]
            ?? ProcessInfo.processInfo.environment["BARSTATE_PRESET_LANGUAGE"]
        {
            let expectedSaveTitle = requestedLanguage == "zh-Hans" ? "保存" : "Save"
            precondition(
                L10n.string("common.save") == expectedSaveTitle,
                "the requested app language must be selected"
            )
            precondition(
                L10n.locale.identifier.hasPrefix(requestedLanguage == "zh-Hans" ? "zh" : "en"),
                "dates and relative times must use the selected app language"
            )
        }

        let previousLanguage = AppLanguage.storedPreference
        defer { previousLanguage.save() }
        AppLanguage.english.save()
        precondition(
            AppLanguage.storedPreference == .english,
            "English language preference must persist"
        )
        AppLanguage.simplifiedChinese.save()
        precondition(
            AppLanguage.storedPreference == .simplifiedChinese,
            "Chinese language preference must persist"
        )
        AppLanguage.system.save()
        precondition(
            AppLanguage.storedPreference == .system,
            "system language preference must clear the override"
        )

        for key in [
            "common.save",
            "popover.refresh_all",
            "editor.validation.valid_https_url",
            "error.script_timeout"
        ] {
            precondition(L10n.string(key) != key, "missing localized value for \(key)")
        }

        for count in [1, 2] {
            let value = L10n.plural("popover.refreshing_count", count: count)
            precondition(value.contains(String(count)), "localized count must be visible")
            precondition(!value.contains("%#@"), "plural format was not resolved")
        }

        let runtime = MonitorRuntimeState(lastError: .request("offline"))
        let data = try JSONEncoder().encode(runtime)
        let decoded = try JSONDecoder().decode(MonitorRuntimeState.self, from: data)
        precondition(
            decoded.lastError == .request("offline"),
            "structured monitoring errors must survive persistence"
        )
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        precondition(object["lastFailure"] != nil, "new errors must use lastFailure")
        precondition(object["lastError"] == nil, "localized error strings must not be persisted")
    }

    private static func testPersistenceRecoveryAndPermissions() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BarStateSmokeTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = PersistenceController(directoryURL: directory)
        let expected = Monitor(name: "saved")

        try persistence.save(monitors: [expected])
        for url in [persistence.fileURL, persistence.backupFileURL] {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let permissions = attributes[.posixPermissions] as? NSNumber
            precondition(permissions?.intValue == 0o600, "state file permissions must be 0600")
        }

        try Data("invalid".utf8).write(to: persistence.fileURL, options: .atomic)
        let recovered = persistence.load()
        precondition(recovered.state.monitors == [expected], "backup recovery failed")
        precondition(recovered.warning != nil, "backup recovery should be visible")
    }

    private static func testPollingGenerationAndConcurrency() async throws {
        let fetcher = SmokeFetcher()
        let recorder = SmokeRecorder()
        let engine = PollingEngine(
            valueFetcher: fetcher,
            maximumConcurrentRequests: 2,
            resultHandler: { id, outcome, _ in
                await recorder.append(id: id, outcome: outcome)
            }
        )
        let changedID = UUID()
        let old = Monitor(id: changedID, name: "old", urlString: "https://example.com/old")
        var changed = old
        changed.urlString = "https://example.com/new"

        await engine.update(monitors: [old])
        try? await Task.sleep(for: .milliseconds(15))
        await engine.update(monitors: [changed])

        let otherMonitors = (0..<6).map {
            Monitor(name: "queued-\($0)", urlString: "https://example.com/\($0)", order: $0 + 1)
        }
        await engine.update(monitors: [changed] + otherMonitors)

        let expectedCount = otherMonitors.count + 1
        let receivedAll = await waitUntil(timeout: .seconds(2)) {
            await recorder.count == expectedCount
        }
        precondition(receivedAll, "startup queue did not drain")
        let maximumConcurrency = await fetcher.maximumConcurrency
        let changedValues = await recorder.values(for: changedID)
        precondition(maximumConcurrency <= 2, "concurrency limit was exceeded")
        precondition(changedValues == [2], "stale request result was accepted")
        await engine.stop()
    }

    @MainActor
    private static func testManualRefreshFeedback() {
        let successID = UUID()
        let failureID = UUID()
        let store = MonitorStore(initialMonitors: [
            Monitor(id: successID, name: "success", order: 0),
            Monitor(id: failureID, name: "failure", order: 1)
        ])

        precondition(store.beginManualRefresh(), "manual refresh should start")
        store.setPollingStatus(
            PollingStatus(revision: 1, refreshingIDs: [successID, failureID])
        )

        let completionDate = Date().addingTimeInterval(1)
        store.record(
            monitorID: successID,
            result: .success(30),
            at: completionDate,
            response: nil
        )
        store.record(
            monitorID: failureID,
            result: .failure(.request("offline")),
            at: completionDate,
            response: nil
        )
        store.setPollingStatus(PollingStatus(revision: 2))

        let expectedSummary = L10n.format(
            "refresh.summary",
            [
                L10n.format("refresh.success_part", Int64(1)),
                L10n.format("refresh.failure_part", Int64(1))
            ].joined(separator: L10n.string("list.accessibility_separator"))
        )
        precondition(
            store.refreshFeedback == expectedSummary,
            "manual refresh feedback must report failures"
        )

        let disabledStore = MonitorStore(initialMonitors: [
            Monitor(name: "disabled", isEnabled: false)
        ])
        precondition(!disabledStore.beginManualRefresh(), "disabled monitors should not refresh")
        precondition(
            disabledStore.refreshFeedback == L10n.string("refresh.none"),
            "empty refresh should explain why it did not start"
        )
    }

    private static func waitUntil(
        timeout: Duration,
        condition: @escaping @Sendable () async -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return await condition()
    }
}

private actor SmokeFetcher: MonitorValueFetching {
    private var active = 0
    private(set) var maximumConcurrency = 0

    func fetchValue(for monitor: Monitor) async -> FetchOutcome {
        active += 1
        maximumConcurrency = max(maximumConcurrency, active)
        let isOld = monitor.urlString.hasSuffix("/old")
        do {
            try await Task.sleep(for: isOld ? .milliseconds(250) : .milliseconds(35))
        } catch {
            // Intentionally return a value after cancellation to verify generation isolation.
        }
        active -= 1
        return FetchOutcome(
            formattedResponse: nil,
            requestedAt: Date(),
            result: .success(isOld ? 1 : 2)
        )
    }
}

private actor SmokeRecorder {
    private var entries: [(UUID, Double)] = []

    func append(id: UUID, outcome: FetchOutcome) {
        guard case let .success(value) = outcome.result else { return }
        entries.append((id, value))
    }

    var count: Int { entries.count }

    func values(for id: UUID) -> [Double] {
        entries.filter { $0.0 == id }.map(\.1)
    }
}
