import AppKit
import BarStateCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: MonitorStore
    @ObservedObject var loginItemManager: LoginItemManager
    @ObservedObject var session: SettingsSessionState
    @State private var selectedID: UUID?
    @State private var pendingDraft: Monitor?
    @State private var pendingDeletion: Monitor?
    @State private var pendingNavigation: PendingNavigation?
    @State private var showsDiscardAlert = false
    @State private var selectedLanguage = AppLanguage.storedPreference
    @State private var showsLanguageRestartAlert = false

    private enum PendingNavigation {
        case select(UUID?)
        case create
        case clone(UUID)
    }

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 210, idealWidth: 230, maxWidth: 270)
            detail
                .frame(minWidth: 620, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 860, minHeight: 620)
        .onAppear {
            loginItemManager.refreshStatus()
            if ProcessInfo.processInfo.arguments.contains("--preview-new-monitor") {
                applyNavigation(.create)
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
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.string("settings.monitors"))
                    .font(.headline)
                Spacer()
                Button(L10n.string("settings.clone")) {
                    guard let selectedID else { return }
                    requestNavigation(.clone(selectedID))
                }
                .disabled(!canCloneSelected)
                .help(L10n.string("settings.clone_help"))

                Button(L10n.string("settings.add")) {
                    requestNavigation(.create)
                }
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
                    .help("\(monitor.name)\n\(sidebarSubtitle(for: monitor))")
                }
            }
            .listStyle(.sidebar)

            Divider()
            sidebarGeneralSettings
            Divider()

            HStack(spacing: 14) {
                Button(L10n.string("common.delete")) {
                    if pendingDraft?.id == selectedID {
                        pendingDraft = nil
                        session.setDirty(false)
                        selectedID = store.orderedMonitors.first?.id
                        return
                    }
                    guard let selectedID, let monitor = store.monitor(id: selectedID) else { return }
                    pendingDeletion = monitor
                }
                .disabled(selectedID == nil)

                Spacer()

                Button(L10n.string("settings.move_up")) {
                    guard let selectedID else { return }
                    store.move(id: selectedID, offset: -1)
                }
                .disabled(!canMoveSelected(by: -1))

                Button(L10n.string("settings.move_down")) {
                    guard let selectedID else { return }
                    store.move(id: selectedID, offset: 1)
                }
                .disabled(!canMoveSelected(by: 1))
            }
            .padding(14)
        }
    }

    private func monitorNameRow(for monitor: Monitor) -> some View {
        HStack(spacing: 6) {
            Text(monitor.name)
                .lineLimit(1)
                .truncationMode(.tail)

            if monitor.sourceKind == .prometheus {
                Text(monitor.sourceKind.displayName)
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
        if let pendingDraft, selectedID == pendingDraft.id {
            MonitorEditorViewV2(
                monitor: pendingDraft,
                requiresInitialSuccessfulTest: true,
                isRefreshing: false,
                nextRefreshAt: nil,
                onDirtyChange: { session.setDirty($0) },
                onCancel: { session.discardChanges() }
            ) { saved in
                self.pendingDraft = nil
                store.add(saved)
                session.setDirty(false)
                selectedID = saved.id
            }
            .id("\(pendingDraft.id)-\(session.discardGeneration)")
        } else if let selectedID, let monitor = store.monitor(id: selectedID) {
            MonitorEditorViewV2(
                monitor: monitor,
                isRefreshing: store.pollingStatus.refreshingIDs.contains(monitor.id),
                nextRefreshAt: store.pollingStatus.nextRefreshAt[monitor.id],
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

    private var sidebarGeneralSettings: some View {
        VStack(alignment: .leading, spacing: 7) {
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

            Toggle(
                L10n.string("settings.launch_at_login"),
                isOn: Binding(
                    get: { loginItemManager.isEnabled },
                    set: { loginItemManager.setEnabled($0) }
                )
            )
            .toggleStyle(.switch)

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
        .background(.bar)
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

    private func canMoveSelected(by offset: Int) -> Bool {
        guard let selectedID,
              let index = store.orderedMonitors.firstIndex(where: { $0.id == selectedID })
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
        guard monitor.isEnabled else { return L10n.string("status.disabled") }
        if store.pollingStatus.refreshingIDs.contains(monitor.id) {
            return L10n.string("status.refreshing")
        }
        if monitor.runtime.consecutiveFailures >= 3 {
            return L10n.string("status.repeated_failure")
        }
        if monitor.runtime.consecutiveFailures > 0 {
            return L10n.format(
                "status.update_failed",
                Int64(monitor.runtime.consecutiveFailures)
            )
        }
        return monitor.displayText
    }

    private func sidebarColor(for monitor: Monitor) -> Color {
        guard monitor.isEnabled else { return .secondary }
        if store.pollingStatus.refreshingIDs.contains(monitor.id) { return .accentColor }
        if monitor.runtime.consecutiveFailures >= 3 { return .red }
        if monitor.runtime.consecutiveFailures > 0 { return .orange }
        return .secondary
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
        switch navigation {
        case let .select(id):
            selectedID = id
        case .create:
            let draft = Monitor.draft(order: store.monitors.count)
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
}
