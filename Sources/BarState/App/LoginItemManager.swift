import AppKit
import BarStateCore
import Combine
import Foundation
import ServiceManagement

@MainActor
final class LoginItemManager: NSObject, ObservableObject {
    @Published private(set) var isEnabled: Bool
    @Published private(set) var errorMessage: String?

    override init() {
        self.isEnabled = SMAppService.mainApp.status == .enabled
        super.init()
        refreshStatus()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refreshStatus()
        } catch {
            refreshStatus()
            errorMessage = error.localizedDescription
        }
    }

    func refreshStatus() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled
        switch status {
        case .requiresApproval:
            errorMessage = L10n.string("login.approval_required")
        case .notFound:
            errorMessage = L10n.string("login.registration_unavailable")
        case .enabled, .notRegistered:
            errorMessage = nil
        @unknown default:
            errorMessage = L10n.string("login.status_unknown")
        }
    }

    @objc private func applicationDidBecomeActive() {
        refreshStatus()
    }
}
