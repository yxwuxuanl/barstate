public enum NotificationPermission: Sendable {
    case unknown, notDetermined, denied, authorized

    public var explanation: String {
        switch self {
        case .unknown: L10n.string("alert.permission.unknown")
        case .notDetermined: L10n.string("alert.permission.not_determined")
        case .denied: L10n.string("alert.permission.denied")
        case .authorized: L10n.string("alert.permission.authorized")
        }
    }
}
