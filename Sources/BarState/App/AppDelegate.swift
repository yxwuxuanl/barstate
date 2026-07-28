import AppKit
import BarStateCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var appController: AppController?
    private var isPreparingToTerminate = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        installMainMenu()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        appController = AppController()
        appController?.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isPreparingToTerminate else { return .terminateLater }
        guard appController?.shouldTerminate() != false else { return .terminateCancel }
        isPreparingToTerminate = true
        Task { @MainActor [weak self, weak sender] in
            guard let self else { return }
            await appController?.prepareForTermination()
            sender?.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()

        let applicationMenuItem = NSMenuItem()
        let applicationMenu = NSMenu()

        let aboutItem = NSMenuItem(
            title: L10n.string("menu.about"),
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        applicationMenu.addItem(aboutItem)

        let settingsItem = NSMenuItem(
            title: L10n.string("menu.settings"),
            action: #selector(showSettings(_:)),
            keyEquivalent: ","
        )
        settingsItem.target = self
        applicationMenu.addItem(settingsItem)

        let refreshItem = NSMenuItem(
            title: L10n.string("menu.refresh_all"),
            action: #selector(refreshAll(_:)),
            keyEquivalent: "r"
        )
        refreshItem.target = self
        applicationMenu.addItem(refreshItem)
        applicationMenu.addItem(.separator())

        applicationMenu.addItem(
            withTitle: L10n.string("menu.quit"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        applicationMenuItem.submenu = applicationMenu
        mainMenu.addItem(applicationMenuItem)

        let editMenuItem = NSMenuItem(
            title: L10n.string("menu.edit"),
            action: nil,
            keyEquivalent: ""
        )
        let editMenu = NSMenu(title: L10n.string("menu.edit"))
        editMenu.addItem(
            menuItem(
                title: L10n.string("menu.undo"),
                action: Selector(("undo:")),
                keyEquivalent: "z"
            )
        )

        let redoItem = menuItem(
            title: L10n.string("menu.redo"),
            action: Selector(("redo:")),
            keyEquivalent: "Z"
        )
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redoItem)
        editMenu.addItem(.separator())

        editMenu.addItem(menuItem(
            title: L10n.string("menu.cut"),
            action: #selector(NSText.cut(_:)),
            keyEquivalent: "x"
        ))
        editMenu.addItem(menuItem(
            title: L10n.string("menu.copy"),
            action: #selector(NSText.copy(_:)),
            keyEquivalent: "c"
        ))
        editMenu.addItem(menuItem(
            title: L10n.string("menu.paste"),
            action: #selector(NSText.paste(_:)),
            keyEquivalent: "v"
        ))
        editMenu.addItem(menuItem(
            title: L10n.string("menu.select_all"),
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        ))

        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        let windowMenuItem = NSMenuItem(
            title: L10n.string("menu.window"),
            action: nil,
            keyEquivalent: ""
        )
        let windowMenu = NSMenu(title: L10n.string("menu.window"))
        windowMenu.addItem(
            menuItem(
                title: L10n.string("menu.close_window"),
                action: #selector(NSWindow.performClose(_:)),
                keyEquivalent: "w"
            )
        )
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }

    @objc private func showSettings(_ sender: Any?) {
        appController?.showSettings()
    }

    @objc private func refreshAll(_ sender: Any?) {
        appController?.refreshAll()
    }

    private func menuItem(
        title: String,
        action: Selector,
        keyEquivalent: String
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = nil
        return item
    }
}
