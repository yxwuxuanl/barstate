import Foundation

public enum MonitorAlertCondition: String, Codable, CaseIterable, Identifiable, Sendable {
    case belowOrEqual, aboveOrEqual, requestFailure
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .belowOrEqual: L10n.string("alert.condition.below")
        case .aboveOrEqual: L10n.string("alert.condition.above")
        case .requestFailure: L10n.string("alert.condition.failure")
        }
    }
}

public struct MonitorAlertRule: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var condition: MonitorAlertCondition
    public var threshold: Double
    public var notifiesRecovery: Bool

    public init(isEnabled: Bool = false, condition: MonitorAlertCondition = .belowOrEqual,
                threshold: Double = 0, notifiesRecovery: Bool = false) {
        self.isEnabled = isEnabled
        self.condition = condition
        self.threshold = threshold
        self.notifiesRecovery = notifiesRecovery
    }
}

public struct MonitorAlertEvent: Equatable, Sendable {
    public enum Kind: Sendable { case abnormal, recovered }
    public let kind: Kind
    public let incidentID: UUID
    public let value: Double?

    public init(kind: Kind, incidentID: UUID, value: Double?) {
        self.kind = kind
        self.incidentID = incidentID
        self.value = value
    }
}

/// Only new runtime samples are passed here. Tests, persisted values and timers never evaluate rules.
public struct MonitorAlertState: Codable, Equatable, Sendable {
    public static let notificationCooldown: TimeInterval = 15 * 60
    public private(set) var isActive = false
    public private(set) var incidentID: UUID?
    public private(set) var didNotify = false
    public private(set) var lastNotifiedAt: Date?
    public private(set) var abnormalSamples = 0
    public private(set) var recoverySamples = 0

    public init() {}

    public mutating func interruptSamples() {
        abnormalSamples = 0
        recoverySamples = 0
    }

    /// Resets observations while retaining the cooldown across configuration changes.
    public mutating func reset() {
        let previousNotification = lastNotifiedAt
        self = .init()
        lastNotifiedAt = previousNotification
    }

    public mutating func evaluate(
        _ result: Result<Double, MonitoringError>, rule: MonitorAlertRule, at now: Date,
        allowsNotification: Bool = true
    ) -> MonitorAlertEvent? {
        guard rule.isEnabled, rule.threshold.isFinite else { reset(); return nil }
        let value: Double?
        let abnormal: Bool
        switch result {
        case .success(let sample) where sample.isFinite:
            value = sample
            switch rule.condition {
            case .belowOrEqual: abnormal = sample <= rule.threshold
            case .aboveOrEqual: abnormal = sample >= rule.threshold
            case .requestFailure: abnormal = false
            }
        default:
            guard rule.condition == .requestFailure else { interruptSamples(); return nil }
            value = nil
            abnormal = true
        }
        let abnormalRequired = rule.condition == .requestFailure ? 3 : 2
        let recoveryRequired = rule.condition == .requestFailure ? 1 : 2
        if abnormal {
            recoverySamples = 0
            abnormalSamples = min(abnormalSamples + 1, abnormalRequired)
            if abnormalSamples >= abnormalRequired, !isActive {
                isActive = true
                incidentID = UUID()
                didNotify = false
            }
            // A cooldown expiring alone never sends; a new qualifying sample is required.
            let cooldownExpired = lastNotifiedAt.map {
                now.timeIntervalSince($0) >= Self.notificationCooldown
            } ?? true
            if isActive, abnormalSamples >= abnormalRequired, !didNotify,
               cooldownExpired, allowsNotification, let incidentID {
                didNotify = true
                lastNotifiedAt = now
                return MonitorAlertEvent(kind: .abnormal, incidentID: incidentID, value: value)
            }
        } else {
            abnormalSamples = 0
            guard isActive else { recoverySamples = 0; return nil }
            recoverySamples = min(recoverySamples + 1, recoveryRequired)
            if recoverySamples >= recoveryRequired {
                isActive = false
                recoverySamples = 0
                if didNotify, rule.notifiesRecovery, allowsNotification, let incidentID {
                    return MonitorAlertEvent(kind: .recovered, incidentID: incidentID, value: value)
                }
            }
        }
        return nil
    }

    public func contains(_ event: MonitorAlertEvent) -> Bool {
        incidentID == event.incidentID && isActive == (event.kind == .abnormal)
    }
}
