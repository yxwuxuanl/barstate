import AppKit
import BarStateCore
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var store: MonitorStore
    @ObservedObject var loginItemManager: LoginItemManager
    @ObservedObject var session: SettingsSessionState
    @State private var selectedID: UUID?
    @State private var showsGeneralSettings = false
    @State private var showsSourceCatalog = false
    @State private var pendingDraft: Monitor?
    @State private var pendingDeletion: Monitor?
    @State private var pendingNavigation: PendingNavigation?
    @State private var showsDiscardAlert = false
    @State private var selectedLanguage = AppLanguage.storedPreference
    @State private var showsLanguageRestartAlert = false
    @State private var showsStartFreshAlert = false
    @State private var isResolvingRecovery = false

    private enum PendingNavigation {
        case select(UUID?)
        case general
        case add
        case create(MonitorCreationKind)
        case clone(UUID)
    }

    private enum MonitorCreationKind {
        case httpAPI
        case prometheus
        case codexQuota
        case jsonTemplate
        case source(MonitorSourceChoice)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let recoveryMode = store.recoveryMode {
                PersistenceRecoveryBanner(
                    mode: recoveryMode,
                    isWorking: isResolvingRecovery,
                    onRestore: restoreRecoveredConfiguration,
                    onExport: exportRecoveredConfiguration,
                    onShowFiles: showConfigurationFiles,
                    onStartFresh: { showsStartFreshAlert = true }
                )
            }

            HSplitView {
                sidebar
                    .frame(minWidth: 210, idealWidth: 220, maxWidth: 270)
                detail
                    .frame(minWidth: 620, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 860, minHeight: 620)
        .sheet(isPresented: $showsSourceCatalog) {
            SourceCatalogView(
                onSelect: { choice in
                    showsSourceCatalog = false
                    requestNavigation(.create(.source(choice)))
                },
                onExample: {
                    showsSourceCatalog = false
                    requestNavigation(.create(.jsonTemplate))
                },
                onCancel: { showsSourceCatalog = false }
            )
        }
        .onAppear {
            loginItemManager.refreshStatus()
            if ProcessInfo.processInfo.arguments.contains("--preview-general") {
                showsGeneralSettings = true
            }
            if ProcessInfo.processInfo.arguments.contains("--preview-new-monitor") {
                applyNavigation(.create(.httpAPI))
                return
            }
            if let requestedMonitorID = session.requestedMonitorID,
               store.monitor(id: requestedMonitorID) != nil
            {
                selectedID = requestedMonitorID
            } else if selectedID == nil {
                selectedID = store.orderedMonitors.first?.id
            }
        }
        .onChange(of: session.selectionGeneration) {
            guard let requestedMonitorID = session.requestedMonitorID,
                  store.monitor(id: requestedMonitorID) != nil
            else { return }
            requestNavigation(.select(requestedMonitorID))
        }
        .onChange(of: session.discardGeneration) {
            pendingDraft = nil
            if let selectedID, store.monitor(id: selectedID) == nil {
                self.selectedID = store.orderedMonitors.first?.id
            }
        }
        .alert(L10n.string("settings.discard_title"), isPresented: $showsDiscardAlert) {
            Button(L10n.string("settings.discard"), role: .destructive) {
                performPendingNavigation()
            }
            Button(L10n.string("common.cancel"), role: .cancel) {
                pendingNavigation = nil
            }
        } message: {
            Text(L10n.string("settings.discard_message"))
        }
        .alert(
            L10n.string("settings.delete_title"),
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { monitor in
            Button(L10n.string("common.delete"), role: .destructive) {
                store.remove(id: monitor.id)
                session.setDirty(false)
                selectedID = store.orderedMonitors.first?.id
                pendingDeletion = nil
            }
            Button(L10n.string("common.cancel"), role: .cancel) {
                pendingDeletion = nil
            }
        } message: { monitor in
            Text(L10n.format("settings.delete_message", monitor.name))
        }
        .alert(
            L10n.string("language.restart_title"),
            isPresented: $showsLanguageRestartAlert
        ) {
            Button(L10n.string("menu.quit")) {
                NSApplication.shared.terminate(nil)
            }
            Button(L10n.string("common.later"), role: .cancel) {}
        } message: {
            Text(L10n.string("language.restart_message"))
        }
        .alert(
            L10n.string("recovery.start_fresh_title"),
            isPresented: $showsStartFreshAlert
        ) {
            Button(L10n.string("recovery.start_fresh"), role: .destructive) {
                startFreshAfterRecovery()
            }
            Button(L10n.string("common.cancel"), role: .cancel) {}
        } message: {
            Text(L10n.string("recovery.start_fresh_message"))
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.string("settings.monitors"))
                    .font(.headline)
                Spacer()
                Button {
                    requestNavigation(.add)
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help(L10n.string("settings.add"))
                .accessibilityLabel(L10n.string("settings.add"))
                .disabled(store.isPersistenceWriteProtected)
                .keyboardShortcut("n", modifiers: .command)
            }
            .padding(14)

            Divider()

            List(selection: sidebarSelection) {
                if let pendingDraft {
                    VStack(alignment: .leading, spacing: 3) {
                        monitorNameRow(for: pendingDraft)
                        Text(L10n.string("common.unsaved"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 3)
                    .tag(pendingDraft.id)
                    .help(L10n.format(
                        "settings.sidebar_help",
                        pendingDraft.name,
                        L10n.string("common.unsaved")
                    ))
                }

                ForEach(store.orderedMonitors) { monitor in
                    VStack(alignment: .leading, spacing: 3) {
                        monitorNameRow(for: monitor)
                        Text(sidebarSubtitle(for: monitor))
                            .font(.caption)
                            .foregroundStyle(sidebarColor(for: monitor))
                            .lineLimit(1)
                    }
                    .padding(.vertical, 3)
                    .tag(monitor.id)
                    .help("\(monitor.name)\n\(sidebarSubtitle(for: monitor))\n\(store.health(for: monitor).detail)")
                    .contextMenu {
                        Button(L10n.string("settings.clone")) {
                            requestNavigation(.clone(monitor.id))
                        }
                        .disabled(store.isPersistenceWriteProtected)
                        Button(L10n.string("settings.move_up")) {
                            store.move(id: monitor.id, offset: -1)
                        }
                        .disabled(
                            store.isPersistenceWriteProtected || !canMove(monitor.id, by: -1)
                        )
                        Button(L10n.string("settings.move_down")) {
                            store.move(id: monitor.id, offset: 1)
                        }
                        .disabled(
                            store.isPersistenceWriteProtected || !canMove(monitor.id, by: 1)
                        )
                        Divider()
                        Button(L10n.string("common.delete"), role: .destructive) {
                            pendingDeletion = monitor
                        }
                        .disabled(store.isPersistenceWriteProtected)
                    }
                }
                .onMove(perform: store.move)
            }
            .listStyle(.sidebar)
            .frame(minHeight: 120)
            .layoutPriority(0)

            Divider()
            HStack(spacing: 10) {
                Button { requestNavigation(.general) } label: {
                    Label(L10n.string("settings.general"), systemImage: "gearshape")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 9)
                        .background(showsGeneralSettings ? Color.accentColor.opacity(0.13) : .clear,
                                    in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                Menu {
                    Button(L10n.string("settings.clone")) {
                        if let selectedID { requestNavigation(.clone(selectedID)) }
                    }.disabled(!canCloneSelected)
                    Button(L10n.string("settings.move_up")) {
                        if let selectedID { store.move(id: selectedID, offset: -1) }
                    }.disabled(!canMoveSelected(by: -1))
                    Button(L10n.string("settings.move_down")) {
                        if let selectedID { store.move(id: selectedID, offset: 1) }
                    }.disabled(!canMoveSelected(by: 1))
                    Divider()
                    Button(L10n.string("common.delete"), role: .destructive) {
                        if pendingDraft?.id == selectedID {
                            pendingDraft = nil
                            session.setDirty(false)
                            selectedID = store.orderedMonitors.first?.id
                        } else if let selectedID {
                            pendingDeletion = store.monitor(id: selectedID)
                        }
                    }.disabled(selectedID == nil)
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel(L10n.string("settings.monitor_actions"))
                .disabled(store.isPersistenceWriteProtected || showsGeneralSettings)
            }
            .padding(10)
        }
    }

    private func monitorNameRow(for monitor: Monitor) -> some View {
        HStack(spacing: 6) {
            Text(monitor.name)
                .lineLimit(1)
                .truncationMode(.tail)

            if monitor.sourceKind != .httpAPI || monitor.preset != nil {
                Text(monitor.sourceDisplayName)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        .quaternary,
                        in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                    )
                    .fixedSize()
                    .layoutPriority(1)
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if store.recoveryMode == .unreadableFiles {
            VStack(spacing: 10) {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(.red)
                    .accessibilityHidden(true)
                Text(L10n.string("recovery.unreadable_title"))
                    .font(.title2.weight(.semibold))
                Text(L10n.string("recovery.unreadable_message"))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if showsGeneralSettings {
            generalSettings
        } else if let pendingDraft, selectedID == pendingDraft.id {
            MonitorEditorViewV2(
                monitor: pendingDraft,
                requiresInitialSuccessfulTest: true,
                isRefreshing: false,
                nextRefreshAt: nil,
                now: store.now,
                isNetworkOffline: store.isNetworkOffline,
                notificationPermission: store.notificationPermission,
                notificationMessage: store.notificationMessage,
                onRequestNotificationPermission: { store.onRequestNotificationPermission?() },
                onDirtyChange: { session.setDirty($0) },
                onCancel: { session.discardChanges() }
            ) { saved in
                self.pendingDraft = nil
                store.add(saved)
                session.setDirty(false)
                selectedID = saved.id
            }
            .id("\(pendingDraft.id)-\(session.discardGeneration)")
            .disabled(store.isPersistenceWriteProtected)
        } else if let selectedID, let monitor = store.monitor(id: selectedID) {
            MonitorEditorViewV2(
                monitor: monitor,
                isRefreshing: store.pollingStatus.refreshingIDs.contains(monitor.id),
                nextRefreshAt: store.pollingStatus.nextRefreshAt[monitor.id],
                now: store.now,
                isNetworkOffline: store.isNetworkOffline,
                notificationPermission: store.notificationPermission,
                notificationMessage: store.notificationMessage,
                onRequestNotificationPermission: { store.onRequestNotificationPermission?() },
                onDirtyChange: { session.setDirty($0) },
                onSwitchesChange: { isEnabled, showsInMenuBar in
                    store.updateSwitches(
                        id: monitor.id,
                        isEnabled: isEnabled,
                        showsInMenuBar: showsInMenuBar
                    )
                },
                onCancel: { session.discardChanges() },
                onSave: { updated in
                    var merged = updated
                    if let stored = store.monitor(id: updated.id) {
                        merged.runtime = stored.runtime
                    }
                    store.update(merged)
                    session.setDirty(false)
                }
            )
            .id("\(selectedID)-\(session.discardGeneration)")
            .disabled(store.isPersistenceWriteProtected)
        } else if store.orderedMonitors.isEmpty {
            FirstMonitorWelcomeView(
                onCreateHTTP: { requestNavigation(.create(.httpAPI)) },
                onCreatePrometheus: { requestNavigation(.create(.prometheus)) },
                onCreateCodexQuota: { requestNavigation(.create(.codexQuota)) },
                onUseJSONTemplate: { requestNavigation(.create(.jsonTemplate)) }
            )
        } else {
            VStack(spacing: 8) {
                Text(L10n.string("settings.select_monitor"))
                    .font(.title3)
                Text(L10n.string("settings.select_monitor_hint"))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var generalSettings: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.string("settings.general"))
                .font(.title2.weight(.semibold))
                .padding(24)
            Divider()
            ScrollView {
                generalSettingsControls
                    .padding(24)
                    .frame(maxWidth: 660)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var generalSettingsControls: some View {
        VStack(alignment: .leading, spacing: 20) {
            Picker(
                L10n.string("settings.language"),
                selection: languageSelection
            ) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.displayName).tag(language)
                }
            }
            .pickerStyle(.menu)
            .help(L10n.string("language.help"))

            Picker(
                L10n.string("settings.menu_bar_presentation"),
                selection: menuBarPresentationBinding
            ) {
                ForEach(MenuBarPresentation.allCases) { presentation in
                    Text(presentation.displayName).tag(presentation)
                }
            }
            .pickerStyle(.menu)

            if store.preferences.menuBarPresentation == .individual {
                Stepper(
                    L10n.format(
                        "settings.menu_bar_characters",
                        Int64(store.preferences.menuBarMaximumCharacters)
                    ),
                    value: menuBarMaximumCharactersBinding,
                    in: AppPreferences.minimumMenuBarCharacters...AppPreferences.maximumMenuBarCharacters,
                    step: 2
                )
                .font(.caption)
            }

            Toggle(
                L10n.string("settings.launch_at_login"),
                isOn: Binding(
                    get: { loginItemManager.isEnabled },
                    set: { loginItemManager.setEnabled($0) }
                )
            )
            .toggleStyle(.switch)

            if store.isPersistenceWriteProtected {
                Text(L10n.string("persistence.recovery_required"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage = loginItemManager.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .help(errorMessage)
            } else if let persistenceMessage = store.persistenceMessage {
                Label(persistenceMessage, systemImage: "externaldrive.badge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(3)
                    .help(persistenceMessage)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }

    private var sidebarSelection: Binding<UUID?> {
        Binding(
            get: { selectedID },
            set: { newSelection in
                guard newSelection != selectedID else { return }
                requestNavigation(.select(newSelection))
            }
        )
    }

    private var languageSelection: Binding<AppLanguage> {
        Binding(
            get: { selectedLanguage },
            set: { newLanguage in
                selectedLanguage = newLanguage
                newLanguage.save()
                showsLanguageRestartAlert = newLanguage != AppLanguage.launchPreference
            }
        )
    }

    private var menuBarPresentationBinding: Binding<MenuBarPresentation> {
        Binding(
            get: { store.preferences.menuBarPresentation },
            set: { presentation in
                var preferences = store.preferences
                preferences.menuBarPresentation = presentation
                store.updatePreferences(preferences)
            }
        )
    }

    private var menuBarMaximumCharactersBinding: Binding<Int> {
        Binding(
            get: { store.preferences.menuBarMaximumCharacters },
            set: { maximumCharacters in
                var preferences = store.preferences
                preferences.menuBarMaximumCharacters = maximumCharacters
                store.updatePreferences(preferences)
            }
        )
    }

    private func canMoveSelected(by offset: Int) -> Bool {
        guard let selectedID else { return false }
        return canMove(selectedID, by: offset)
    }

    private func canMove(_ monitorID: UUID, by offset: Int) -> Bool {
        guard let index = store.orderedMonitors.firstIndex(where: { $0.id == monitorID })
        else { return false }
        return store.orderedMonitors.indices.contains(index + offset)
    }

    private var canCloneSelected: Bool {
        guard let selectedID else { return false }
        return store.monitor(id: selectedID) != nil
    }

    private func uniqueCloneName(for monitor: Monitor) -> String {
        let existingNames = Set(store.monitors.map(\.name))
        let baseName = L10n.format("settings.clone_name", monitor.name)
        guard existingNames.contains(baseName) else { return baseName }

        var suffix: Int64 = 2
        while true {
            let candidate = L10n.format(
                "settings.clone_name_numbered",
                monitor.name,
                suffix
            )
            if !existingNames.contains(candidate) {
                return candidate
            }
            suffix += 1
        }
    }

    private func sidebarSubtitle(for monitor: Monitor) -> String {
        let health = store.health(for: monitor)
        switch health.phase {
        case .healthy: return monitor.displayText
        case .stale, .offline, .retrying:
            return "\(health.title) · \(monitor.displayText)"
        default: return health.title
        }
    }

    private func sidebarColor(for monitor: Monitor) -> Color {
        switch store.health(for: monitor).phase {
        case .failed: .red
        case .retrying, .stale, .offline: .orange
        case .refreshing: .accentColor
        default: .secondary
        }
    }

    private func requestNavigation(_ navigation: PendingNavigation) {
        if session.isDirty {
            pendingNavigation = navigation
            showsDiscardAlert = true
        } else {
            applyNavigation(navigation)
        }
    }

    private func performPendingNavigation() {
        guard let pendingNavigation else { return }
        session.setDirty(false)
        self.pendingNavigation = nil
        applyNavigation(pendingNavigation)
    }

    private func applyNavigation(_ navigation: PendingNavigation) {
        pendingDraft = nil
        showsGeneralSettings = false
        switch navigation {
        case .general:
            selectedID = nil
            showsGeneralSettings = true
        case .add:
            showsSourceCatalog = true
        case let .select(id):
            selectedID = id
        case let .create(kind):
            let draft = makeDraft(kind: kind)
            pendingDraft = draft
            selectedID = draft.id
            session.setDirty(true)
        case let .clone(id):
            guard let source = store.monitor(id: id) else {
                selectedID = store.orderedMonitors.first?.id
                return
            }
            let draft = makeMonitorClone(
                from: source,
                name: uniqueCloneName(for: source),
                order: store.monitors.count
            )
            pendingDraft = draft
            selectedID = draft.id
            session.setDirty(true)
        }
    }

    private func makeDraft(kind: MonitorCreationKind) -> Monitor {
        var draft = Monitor.draft(order: store.monitors.count)
        switch kind {
        case let .source(choice):
            return choice.makeMonitor(order: store.monitors.count)
        case .httpAPI:
            draft.sourceKind = .httpAPI
        case .prometheus:
            draft.sourceKind = .prometheus
            draft.urlString = "https://"
        case .codexQuota:
            draft.sourceKind = .codexQuota
            draft.name = L10n.string("monitor.codex_quota_name")
            draft.urlString = CodexQuota.endpointURLString
            draft.displayTemplate = L10n.string("monitor.codex_quota_template")
            draft.refreshInterval = 5 * 60
            draft.refreshIntervalUnit = .minutes
        case .jsonTemplate:
            draft.sourceKind = .httpAPI
            draft.name = L10n.string("monitor.json_template_name")
            draft.urlString = "https://api.example.com/value"
            draft.parser = ParserConfiguration(jsonPath: "$.data.value")
            draft.displayTemplate = Monitor.valuePlaceholder
        }
        return draft
    }

    private func restoreRecoveredConfiguration() {
        isResolvingRecovery = true
        Task { @MainActor in
            await store.restoreRecoveredConfiguration()
            isResolvingRecovery = false
        }
    }

    private func startFreshAfterRecovery() {
        isResolvingRecovery = true
        Task { @MainActor in
            await store.startFreshAfterRecovery()
            selectedID = nil
            pendingDraft = nil
            session.setDirty(false)
            isResolvingRecovery = false
        }
    }

    private func showConfigurationFiles() {
        NSWorkspace.shared.open(store.configurationDirectoryURL)
    }

    private func exportRecoveredConfiguration() {
        let panel = NSSavePanel()
        panel.title = L10n.string("recovery.export_title")
        panel.nameFieldStringValue = "BarState-recovered.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let destinationURL = panel.url else { return }
        do {
            try store.exportConfiguration(to: destinationURL)
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }
}
