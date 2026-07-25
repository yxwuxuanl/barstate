import AppKit
import BarStateCore
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let store: MonitorStore
    private let loginItemManager: LoginItemManager
    private let session = SettingsSessionState()
    private var window: NSWindow?

    init(store: MonitorStore, loginItemManager: LoginItemManager) {
        self.store = store
        self.loginItemManager = loginItemManager
    }

    func show(monitorID: UUID? = nil) {
        NSApp.setActivationPolicy(.regular)

        if let monitorID {
            session.requestSelection(monitorID)
        }

        if window == nil {
            let rootView = SettingsView(
                store: store,
                loginItemManager: loginItemManager,
                session: session
            )
            let hostingController = NSHostingController(rootView: rootView)
            let window = NSWindow(contentViewController: hostingController)
            window.title = L10n.string("settings.window_title")
            let previewsCompactLayout = ProcessInfo.processInfo.arguments.contains("--preview-compact")
            window.setContentSize(
                previewsCompactLayout
                    ? NSSize(width: 860, height: 620)
                    : NSSize(width: 1_120, height: 760)
            )
            window.minSize = NSSize(width: 860, height: 620)
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func captureContent(to url: URL) throws {
        guard let contentView = window?.contentView else {
            throw SettingsCaptureError.windowUnavailable
        }
        contentView.layoutSubtreeIfNeeded()
        let bounds = contentView.bounds
        guard let representation = contentView.bitmapImageRepForCachingDisplay(in: bounds) else {
            throw SettingsCaptureError.cannotCreateBitmap
        }
        contentView.cacheDisplay(in: bounds, to: representation)
        guard let data = representation.representation(using: .png, properties: [:]) else {
            throw SettingsCaptureError.cannotEncodePNG
        }
        try data.write(to: url, options: .atomic)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        confirmDiscardIfNeeded()
    }

    func confirmDiscardIfNeeded() -> Bool {
        guard session.isDirty else { return true }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.string("settings.discard_title")
        alert.informativeText = L10n.string("settings.discard_message")
        alert.addButton(withTitle: L10n.string("settings.discard"))
        alert.addButton(withTitle: L10n.string("common.cancel"))

        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        session.discardChanges()
        return true
    }
}

private enum SettingsCaptureError: Error {
    case windowUnavailable
    case cannotCreateBitmap
    case cannotEncodePNG
}
