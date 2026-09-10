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
    private var notificationService: MonitorNotificationService?
    private var clockTask: Task<Void, Never>?
    private var activationObserver: NSObjectProtocol?
    private let isPreviewMode: Bool
    private let isNotificationSmoke: Bool
    private let previewsSettings: Bool
    private var notificationSmokeEvents: [String] = []
    private let settingsCapturePath: String?
    private let firstLaunchSettingsPolicy: FirstLaunchSettingsPolicy

    init(userDefaults: UserDefaults = .standard) {
        let arguments = ProcessInfo.processInfo.arguments
        let previewsSettings = arguments.contains("--preview-settings")
        let isNotificationSmoke = arguments.contains("--notification-smoke")
        let isPreviewMode = arguments.contains("--preview") || previewsSettings || isNotificationSmoke
        self.isNotificationSmoke = isNotificationSmoke
        self.isPreviewMode = isPreviewMode
        if isPreviewMode {
            NSApp.appearance = NSAppearance(named: arguments.contains("--preview-dark") ? .darkAqua : .aqua)
        }
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
        var previewMonitors = arguments.contains("--preview-empty")
            ? []
            : Self.previewMonitors
        if let providerArgument = arguments.first(where: { $0.hasPrefix("--preview-provider=") }),
           let provider = DataSourceProvider(rawValue: String(providerArgument.dropFirst("--preview-provider=".count))) {
            let preset = DataSourcePreset(provider: provider, apiKey: "preview-key")
            previewMonitors.insert(Monitor(name: provider.displayName, preset: preset, urlString: provider.endpoint,
                                           displayTemplate: preset.defaultDisplayTemplate,
                                           refreshInterval: 300, refreshIntervalUnit: .minutes,
                                           runtime: .init(lastValue: 24.8, lastSuccessAt: Date())), at: 0)
            for index in previewMonitors.indices { previewMonitors[index].order = index }
        }
        if isNotificationSmoke {
            previewMonitors = [
                Monitor(name: "Unrelated notification check", isEnabled: false),
                Monitor(name: "BarState notification check",
                        alertRule: .init(isEnabled: true, condition: .requestFailure, notifiesRecovery: true),
                        order: 1)
            ]
        }
        if arguments.contains("--preview-alerts"), !previewMonitors.isEmpty {
            previewMonitors[0].alertRule = .init(isEnabled: true, threshold: 20)
        }
        let store = MonitorStore(initialMonitors: isPreviewMode ? previewMonitors : nil)
        self.store = store
        self.loginItemManager = LoginItemManager()

        let apiClient = APIClient()
        self.pollingEngine = PollingEngine(
            valueFetcher: apiClient,
            resultHandler: { [weak store] monitor, outcome, date in
                await store?.record(
                    requestedMonitor: monitor,
                    result: outcome.result,
                    at: date,
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

        if !isPreviewMode || isNotificationSmoke {
            notificationService = MonitorNotificationService(store: store) { [weak self] id in
                self?.showSettings(monitorID: id)
                self?.recordNotificationSmokeEvent("clicked")
            }
            store.onAlert = { [weak self] monitor, event in
                Task { await self?.notificationService?.deliver(event, for: monitor) }
            }
            store.onRequestNotificationPermission = { [weak self] in
                Task { await self?.notificationService?.requestPermission() }
            }
        }

        store.onConfigurationChange = { [weak self] monitors in
            guard let self else { return }
            Task {
                if !self.isPreviewMode { await self.pollingEngine.update(monitors: monitors) }
                await self.notificationService?.reconcile(monitors: monitors)
            }
        }

        networkStatusMonitor = NetworkStatusMonitor(onStatusChange: { [weak store] offline in
            Task { @MainActor in store?.setNetworkOffline(offline) }
        }) { [weak pollingEngine] in
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
                self.store.tick()
                await self.pollingEngine.refreshOverdue()
            }
        }
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.notificationService?.refreshPermission() }
        }
    }

    func start() {
        clockTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.store.tick()
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
        if isNotificationSmoke {
            recordNotificationSmokeEvent("started")
            showSettings()
            Task {
                await notificationService?.requestPermission()
                guard store.notificationPermission == .authorized,
                      let monitor = store.monitors.first(where: { $0.alertRule.isEnabled }) else {
                    recordNotificationSmokeEvent("permission-not-authorized")
                    print("Notification check: permission not authorized")
                    return
                }
                recordNotificationSmokeEvent("authorized")
                for _ in 0..<3 {
                    store.record(requestedMonitor: monitor, result: .failure(.requestTimedOut), at: Date(), response: nil)
                }
                print("Notification check: submitted isolated failure incident")
                recordNotificationSmokeEvent("incident-submitted")
                for _ in 0..<10 {
                    if await notificationService?.hasDeliveredNotification(for: monitor.id) == true {
                        recordNotificationSmokeEvent("system-delivered")
                        return
                    }
                    try? await Task.sleep(for: .seconds(1))
                }
                recordNotificationSmokeEvent("delivery-not-observed")
            }
            return
        }
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
                                if ProcessInfo.processInfo.arguments.contains("--exit-after-capture") {
                                    NSApp.terminate(nil)
                                }
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
            await notificationService?.refreshPermission()
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

    private func recordNotificationSmokeEvent(_ event: String) {
        guard isNotificationSmoke else { return }
        notificationSmokeEvents.append(event)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("barstate-notification-check.json")
        // Test-only lifecycle markers; no monitor data or credentials are written here.
        if let data = try? JSONEncoder().encode(notificationSmokeEvents) {
            try? data.write(to: file, options: .atomic)
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
        clockTask?.cancel()
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
