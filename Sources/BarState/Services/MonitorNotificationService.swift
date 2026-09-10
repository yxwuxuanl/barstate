import AppKit
import BarStateCore
// Older macOS SDKs lack Sendable annotations on immutable notification results.
@preconcurrency import UserNotifications

@MainActor
final class MonitorNotificationService: NSObject, UNUserNotificationCenterDelegate {
    private let center: UNUserNotificationCenter
    private weak var store: MonitorStore?
    private let onOpenMonitor: (UUID) -> Void

    init(store: MonitorStore, onOpenMonitor: @escaping (UUID) -> Void) {
        self.store = store
        self.center = .current()
        self.onOpenMonitor = onOpenMonitor
        super.init()
        center.delegate = self
    }

    func refreshPermission() async {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: store?.notificationPermission = .authorized
        case .denied: store?.notificationPermission = .denied
        case .notDetermined: store?.notificationPermission = .notDetermined
        @unknown default: store?.notificationPermission = .unknown
        }
    }

    func requestPermission() async {
        do { _ = try await center.requestAuthorization(options: [.alert, .sound]) }
        catch { store?.notificationMessage = L10n.string("alert.permission.failed") }
        await refreshPermission()
    }

    func deliver(_ event: MonitorAlertEvent, for monitor: Monitor) async {
        await refreshPermission()
        guard store?.canDeliver(event, for: monitor) == true else { return }
        let content = UNMutableNotificationContent()
        content.title = monitor.name
        content.body = Self.body(for: event, monitor: monitor)
        content.sound = .default
        content.userInfo = ["monitorID": monitor.id.uuidString]
        content.threadIdentifier = monitor.id.uuidString
        let identifier = Self.identifier(for: monitor.id)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        do {
            try await center.add(request)
            // Settings can change while the system accepts the request.
            if store?.canDeliver(event, for: monitor) != true {
                center.removePendingNotificationRequests(withIdentifiers: [identifier])
                center.removeDeliveredNotifications(withIdentifiers: [identifier])
            }
        } catch { store?.notificationMessage = L10n.string("alert.delivery_failed") }
    }

    func reconcile(monitors: [Monitor]) async {
        let valid = Set(monitors.filter { $0.isEnabled && $0.alertRule.isEnabled }.map { Self.identifier(for: $0.id) })
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { !valid.contains($0) })
        let delivered = await center.deliveredNotifications()
        center.removeDeliveredNotifications(withIdentifiers: delivered.map { $0.request.identifier }.filter { !valid.contains($0) })
    }

    func hasDeliveredNotification(for monitorID: UUID) async -> Bool {
        let delivered = await center.deliveredNotifications()
        return delivered.contains { $0.request.identifier == Self.identifier(for: monitorID) }
    }

    static func body(for event: MonitorAlertEvent, monitor: Monitor) -> String {
        if event.kind == .recovered { return L10n.string("alert.notification.recovered") }
        if monitor.alertRule.condition == .requestFailure {
            // Do not include server-controlled error text, URLs, response data or credentials.
            return L10n.string("alert.notification.failure")
        }
        let value = event.value.map { NumberDisplayFormatter.string(from: $0) } ?? "--"
        return L10n.format("alert.notification.value", value,
                           monitor.alertRule.condition.title,
                           NumberDisplayFormatter.string(from: monitor.alertRule.threshold))
    }

    private static func identifier(for id: UUID) -> String { "BarState.alert.\(id.uuidString)" }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let id = (response.notification.request.content.userInfo["monitorID"] as? String).flatMap(UUID.init(uuidString:))
        Task { @MainActor [weak self] in
            guard let self, let id, self.store?.monitor(id: id) != nil else { return }
            self.onOpenMonitor(id)
        }
        completionHandler()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}
