import AppKit
import BarStateCore

@MainActor
final class AppController {
    let store: MonitorStore
    let loginItemManager: LoginItemManager

    private let pollingEngine: PollingEngine
    private var statusBarController: StatusBarController!
    private var settingsWindowController: SettingsWindowController!
    private var wakeObserver: NSObjectProtocol?
    private var networkStatusMonitor: NetworkStatusMonitor?
    private let isPreviewMode: Bool
    private let previewsSettings: Bool
    private let settingsCapturePath: String?
    private let firstLaunchSettingsPolicy: FirstLaunchSettingsPolicy

    init(userDefaults: UserDefaults = .standard) {
        let arguments = ProcessInfo.processInfo.arguments
        let previewsSettings = arguments.contains("--preview-settings")
        let isPreviewMode = arguments.contains("--preview") || previewsSettings
        self.isPreviewMode = isPreviewMode
        self.previewsSettings = previewsSettings
        self.firstLaunchSettingsPolicy = FirstLaunchSettingsPolicy(defaults: userDefaults)
        if let captureArgument = arguments.first(where: { $0.hasPrefix("--capture-settings=") }) {
            let requestedPath = captureArgument
                .dropFirst("--capture-settings=".count)
                .description
            self.settingsCapturePath = requestedPath == "auto"
                ? FileManager.default.temporaryDirectory
                    .appendingPathComponent("barstate-settings-preview.png")
                    .path
                : requestedPath
        } else {
            self.settingsCapturePath = nil
        }
        let previewMonitors = arguments.contains("--preview-empty")
            ? []
            : Self.previewMonitors
        let store = MonitorStore(initialMonitors: isPreviewMode ? previewMonitors : nil)
        self.store = store
        self.loginItemManager = LoginItemManager()

        let apiClient = APIClient()
        self.pollingEngine = PollingEngine(
            valueFetcher: apiClient,
            resultHandler: { [weak store] id, outcome, date in
                await store?.record(
                    monitorID: id,
                    result: outcome.result,
                    at: outcome.requestedAt,
                    response: outcome.response,
                    requestDuration: outcome.requestDuration
                )
            },
            statusHandler: { [weak store] status in
                Task { @MainActor in
                    store?.setPollingStatus(status)
                }
            }
        )

        self.statusBarController = StatusBarController(
            store: store,
            onRefreshAll: { [weak self] in self?.refreshAll() },
            onRefreshMonitor: { [weak self] monitorID in
                self?.refresh(monitorID: monitorID)
            },
            onOpenSettings: { [weak self] monitorID in
                self?.showSettings(monitorID: monitorID)
            }
        )
        self.settingsWindowController = SettingsWindowController(
            store: store,
            loginItemManager: loginItemManager
        )

        store.onConfigurationChange = { [weak self] monitors in
            guard let self else { return }
            Task {
                await self.pollingEngine.update(monitors: monitors)
            }
        }

        networkStatusMonitor = NetworkStatusMonitor { [weak pollingEngine] in
            Task {
                await pollingEngine?.refreshAfterConnectivityRestored()
            }
        }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                await self.pollingEngine.refreshOverdue()
            }
        }
    }

    func start() {
        if isPreviewMode {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self else { return }
                if self.previewsSettings {
                    self.showSettings()
                    if let settingsCapturePath = self.settingsCapturePath {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                            do {
                                try self?.settingsWindowController.captureContent(
                                    to: URL(fileURLWithPath: settingsCapturePath)
                                )
                                print("Saved settings preview to \(settingsCapturePath)")
                            } catch {
                                print("Could not save settings preview: \(error)")
                            }
                        }
                    }
                } else {
                    NSApp.activate(ignoringOtherApps: true)
                    self.statusBarController.showPopoverForPreview()
                }
            }
            return
        }
        Task {
            await pollingEngine.update(
                monitors: store.isPersistenceWriteProtected ? [] : store.orderedMonitors
            )
        }
        networkStatusMonitor?.start()

        if firstLaunchSettingsPolicy.consumeShouldShowSettings() {
            DispatchQueue.main.async { [weak self] in
                self?.showSettings()
            }
        }
    }

    func refreshAll() {
        guard store.beginManualRefresh() else { return }
        Task {
            await pollingEngine.refreshAll()
        }
    }

    func refresh(monitorID: UUID) {
        guard !store.isPersistenceWriteProtected,
              store.monitor(id: monitorID)?.isEnabled == true
        else { return }
        Task {
            await pollingEngine.refresh(id: monitorID)
        }
    }

    func showSettings(monitorID: UUID? = nil) {
        settingsWindowController.show(monitorID: monitorID)
    }

    func prepareForTermination() async {
        statusBarController.stop()
        networkStatusMonitor?.cancel()
        await pollingEngine.stop()
        await store.flushPersistence()
    }

    func shouldTerminate() -> Bool {
        settingsWindowController.confirmDiscardIfNeeded()
    }

    private static var previewMonitors: [Monitor] {
        let now = Date()
        var monitors = [
            Monitor(
                name: L10n.string("preview.temperature.name"),
                urlString: "https://example.com/temperature",
                requestHeaders: [
                    RequestHeader(name: "Authorization", value: "Bearer preview-token"),
                    RequestHeader(name: "X-Request-Time", value: "${TIMESTAMP}")
                ],
                parser: ParserConfiguration(jsonPath: "$.temperature"),
                displayTemplate: L10n.string("preview.temperature.template"),
                statusIndicator: StatusIndicatorConfiguration(
                    isEnabled: true,
                    rules: [
                        StatusIndicatorRule(value: 25, color: .blue),
                        StatusIndicatorRule(value: 30, color: .orange),
                        StatusIndicatorRule(value: 35, color: .red)
                    ]
                ),
                showsInMenuBar: true,
                order: 0,
                runtime: MonitorRuntimeState(
                    lastValue: 30,
                    lastSuccessAt: now,
                    lastAttemptAt: now,
                    lastResponse: HTTPResponseSnapshot(
                        requestedAt: now,
                        requestDuration: 0.238,
                        statusCode: 200,
                        reasonPhrase: "OK",
                        httpVersion: "HTTP/2",
                        headers: [
                            HTTPResponseHeader(name: "Content-Type", value: "application/json; charset=utf-8"),
                            HTTPResponseHeader(name: "Cache-Control", value: "no-store"),
                            HTTPResponseHeader(name: "X-Request-ID", value: "preview-1234")
                        ],
                        bodyText: """
                        {
                          "city" : "\(L10n.string("preview.temperature.city"))",
                          "temperature" : 30,
                          "updated_at" : "2026-07-24T14:30:00+08:00"
                        }
                        """,
                        bodyKind: .json
                    )
                )
            ),
            Monitor(
                name: L10n.string("preview.quota.name"),
                urlString: "https://example.com/quota",
                displayTemplate: L10n.string("preview.quota.template"),
                showsInMenuBar: true,
                order: 1,
                runtime: MonitorRuntimeState(
                    lastValue: 30,
                    lastSuccessAt: now.addingTimeInterval(-120),
                    lastAttemptAt: now.addingTimeInterval(-120),
                    lastResponse: HTTPResponseSnapshot(
                        requestedAt: now.addingTimeInterval(-120),
                        requestDuration: 0.412,
                        statusCode: 200,
                        reasonPhrase: "OK",
                        httpVersion: "HTTP/2",
                        headers: [
                            HTTPResponseHeader(
                                name: "Content-Type",
                                value: "application/json; charset=utf-8"
                            )
                        ],
                        bodyText: """
                        {
                          "remaining_percent" : 30
                        }
                        """,
                        bodyKind: .json
                    )
                )
            ),
            Monitor(
                name: L10n.string("preview.exchange_rate.name"),
                urlString: "https://example.com/exchange-rate",
                displayTemplate: "USD/CNY ${value}",
                order: 2,
                runtime: MonitorRuntimeState(
                    lastValue: 7.24,
                    lastSuccessAt: now.addingTimeInterval(-600),
                    lastAttemptAt: now,
                    lastRequestDuration: 10,
                    consecutiveFailures: 1,
                    lastError: .legacy(L10n.string("preview.error.request_timeout"))
                )
            ),
            Monitor(
                name: L10n.string("preview.server_load.name"),
                urlString: "https://example.com/load",
                displayTemplate: L10n.string("preview.server_load.template"),
                order: 3,
                runtime: MonitorRuntimeState(
                    lastValue: 72,
                    lastSuccessAt: now.addingTimeInterval(-3_600),
                    lastAttemptAt: now,
                    lastRequestDuration: 10,
                    consecutiveFailures: 3,
                    lastError: .legacy(L10n.string("preview.error.repeated_failure"))
                )
            )
        ]
        if ProcessInfo.processInfo.arguments.contains("--preview-prometheus") {
            monitors.append(Monitor(
                name: L10n.string("preview.prometheus.name"),
                sourceKind: .prometheus,
                urlString: "https://prometheus.example.com",
                promQL: #"sum(rate(http_requests_total{job="api",status=~"5.."}[5m]))"#,
                requestHeaders: [
                    RequestHeader(name: "Authorization", value: "Bearer preview-token")
                ],
                displayTemplate: L10n.string("preview.prometheus.template"),
                showsInMenuBar: true,
                order: -1,
                runtime: MonitorRuntimeState(
                    lastValue: 0.023,
                    lastSuccessAt: now,
                    lastAttemptAt: now,
                    lastResponse: HTTPResponseSnapshot(
                        requestedAt: now,
                        requestDuration: 0.186,
                        statusCode: 200,
                        reasonPhrase: "OK",
                        httpVersion: "HTTP/2",
                        headers: [
                            HTTPResponseHeader(
                                name: "Content-Type",
                                value: "application/json; charset=utf-8"
                            )
                        ],
                        bodyText: """
                        {
                          "data" : {
                            "result" : [
                              {
                                "metric" : {},
                                "value" : [ 1753511520.0, "0.023" ]
                              }
                            ],
                            "resultType" : "vector"
                          },
                          "status" : "success"
                        }
                        """,
                        bodyKind: .json
                    )
                )
            ))
        }
        return monitors
    }
}
