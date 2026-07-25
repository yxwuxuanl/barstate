import AppKit
import BarStateCore
import Combine
import SwiftUI

@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    private struct Entry {
        let item: NSStatusItem
        let target: StatusItemTarget
        let visibilityObservation: NSKeyValueObservation?
    }

    private let store: MonitorStore
    private let popover = NSPopover()
    private let onRefreshAll: () -> Void
    private let onOpenSettings: (UUID?) -> Void
    private var entries: [UUID: Entry] = [:]
    private var fallbackEntry: Entry?
    private var monitorsCancellable: AnyCancellable?
    private weak var currentAnchor: NSStatusBarButton?
    private var globalMouseMonitor: Any?
    private var appResignObserver: NSObjectProtocol?
    private var workspaceActivationObserver: NSObjectProtocol?

    init(
        store: MonitorStore,
        onRefreshAll: @escaping () -> Void,
        onOpenSettings: @escaping (UUID?) -> Void
    ) {
        self.store = store
        self.onRefreshAll = onRefreshAll
        self.onOpenSettings = onOpenSettings
        super.init()

        popover.behavior = .transient
        popover.delegate = self
        popover.animates = true
        popover.contentSize = NSSize(
            width: MonitorPopoverMetrics.width,
            height: MonitorPopoverMetrics.baseHeight + MonitorPopoverMetrics.emptyHeight
        )
        popover.contentViewController = NSHostingController(
            rootView: MonitorPopoverView(
                store: store,
                onRefreshAll: onRefreshAll,
                onOpenSettings: { [weak self] monitorID in
                    guard let self else { return }
                    self.closePopover()
                    self.onOpenSettings(monitorID)
                }
            )
        )

        monitorsCancellable = Publishers.CombineLatest(
            store.$monitors,
            store.$persistenceMessage
        ).sink { [weak self] monitors, persistenceMessage in
            Task { @MainActor in
                self?.synchronize(
                    with: monitors,
                    persistenceMessage: persistenceMessage
                )
            }
        }
    }

    isolated deinit {
        stopDismissMonitoring()
    }

    func showPopoverForPreview() {
        let button = entries.values.first?.item.button ?? fallbackEntry?.item.button
        guard let button else { return }
        togglePopover(relativeTo: button)
    }

    private func synchronize(with monitors: [Monitor], persistenceMessage: String?) {
        let listHeight = MonitorPopoverMetrics.listHeight(for: monitors.count)
        let messageHeight = Self.persistenceMessageHeight(for: persistenceMessage)
        popover.contentSize = NSSize(
            width: MonitorPopoverMetrics.width,
            height: MonitorPopoverMetrics.baseHeight + listHeight + messageHeight
        )

        let visibleMonitors = monitors
            .filter { $0.isEnabled && $0.showsInMenuBar }
            .sorted { $0.order < $1.order }
        let visibleIDs = Set(visibleMonitors.map(\.id))

        let staleIDs = entries.keys.filter { !visibleIDs.contains($0) }
        for id in staleIDs {
            guard let entry = entries.removeValue(forKey: id) else { continue }
            NSStatusBar.system.removeStatusItem(entry.item)
        }

        for monitor in visibleMonitors {
            if let entry = entries[monitor.id] {
                entry.item.button?.title = monitor.menuBarTitle
                entry.item.button?.toolTip = monitor.name
                entry.item.button?.setAccessibilityLabel(
                    "\(monitor.name)：\(monitor.menuBarTitle)"
                )
            } else {
                entries[monitor.id] = makeEntry(for: monitor)
            }
        }

        if visibleMonitors.isEmpty {
            if fallbackEntry == nil {
                fallbackEntry = makeFallbackEntry()
            }
        } else if let fallbackEntry {
            NSStatusBar.system.removeStatusItem(fallbackEntry.item)
            self.fallbackEntry = nil
        }
    }

    private func makeEntry(for monitor: Monitor) -> Entry {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "BarState.monitor.\(monitor.id.uuidString)"
        item.behavior = [.removalAllowed]
        item.button?.title = monitor.menuBarTitle
        item.button?.toolTip = monitor.name
        item.button?.setAccessibilityLabel("\(monitor.name)：\(monitor.menuBarTitle)")
        item.button?.setAccessibilityHelp(L10n.string("statusbar.open_monitor_list"))

        let target = StatusItemTarget { [weak self] button in
            self?.togglePopover(relativeTo: button)
        }
        item.button?.target = target
        item.button?.action = #selector(StatusItemTarget.performAction(_:))
        item.isVisible = true

        let observation = item.observe(\.isVisible, options: [.old, .new]) { [weak store] _, change in
            guard change.oldValue == true, change.newValue == false else { return }
            Task { @MainActor in
                guard var removedMonitor = store?.monitor(id: monitor.id) else { return }
                removedMonitor.showsInMenuBar = false
                store?.update(removedMonitor)
            }
        }
        return Entry(item: item, target: target, visibilityObservation: observation)
    }

    private func makeFallbackEntry() -> Entry {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "BarState.fallback"
        item.button?.title = "BarState"
        item.button?.toolTip = L10n.string("statusbar.open_barstate")
        item.button?.setAccessibilityLabel("BarState")
        item.button?.setAccessibilityHelp(L10n.string("statusbar.open_monitor_list"))

        let target = StatusItemTarget { [weak self] button in
            self?.togglePopover(relativeTo: button)
        }
        item.button?.target = target
        item.button?.action = #selector(StatusItemTarget.performAction(_:))
        item.isVisible = true
        return Entry(item: item, target: target, visibilityObservation: nil)
    }

    private static func persistenceMessageHeight(for message: String?) -> CGFloat {
        guard let message else { return 0 }
        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let bounds = (message as NSString).boundingRect(
            with: NSSize(width: MonitorPopoverMetrics.width - 90, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        let maximumTextHeight = ceil(font.boundingRectForFont.height * 3)
        return max(34, ceil(min(bounds.height, maximumTextHeight)) + 20)
    }

    private func togglePopover(relativeTo button: NSStatusBarButton) {
        if popover.isShown, currentAnchor === button {
            closePopover()
            return
        }

        if popover.isShown {
            popover.performClose(nil)
        }
        currentAnchor = button
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        startDismissMonitoring()
    }

    private func closePopover() {
        guard popover.isShown else {
            currentAnchor = nil
            stopDismissMonitoring()
            return
        }
        popover.performClose(nil)
    }

    private func startDismissMonitoring() {
        guard globalMouseMonitor == nil else { return }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                self?.closePopover()
            }
        }

        appResignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.closePopover()
            }
        }

        workspaceActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication,
                application.processIdentifier != ProcessInfo.processInfo.processIdentifier
            else { return }

            Task { @MainActor in
                self?.closePopover()
            }
        }
    }

    private func stopDismissMonitoring() {
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
        if let appResignObserver {
            NotificationCenter.default.removeObserver(appResignObserver)
            self.appResignObserver = nil
        }
        if let workspaceActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceActivationObserver)
            self.workspaceActivationObserver = nil
        }
    }

    func popoverDidClose(_ notification: Notification) {
        currentAnchor = nil
        stopDismissMonitoring()
    }
}

@MainActor
private final class StatusItemTarget: NSObject {
    private let action: (NSStatusBarButton) -> Void

    init(action: @escaping (NSStatusBarButton) -> Void) {
        self.action = action
    }

    @objc func performAction(_ sender: NSStatusBarButton) {
        action(sender)
    }
}
