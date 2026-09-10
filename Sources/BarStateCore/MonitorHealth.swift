import Foundation

/// One presentation model for all runtime surfaces; freshness is independent of request state.
public struct MonitorHealth: Equatable, Sendable {
    public enum Phase: Sendable { case disabled, offline, refreshing, failed, retrying, stale, healthy, waiting }
    public let phase: Phase
    public let isStale: Bool
    public let showsPreviousValue: Bool
    public let lastSuccessAt: Date?
    public let error: MonitoringError?

    public init(monitor: Monitor, now: Date, isRefreshing: Bool = false, isNetworkOffline: Bool = false) {
        let runtime = monitor.runtime
        lastSuccessAt = runtime.lastSuccessAt
        error = runtime.lastError
        let age = runtime.lastSuccessAt.map { now.timeIntervalSince($0) }
        // A future timestamp after a clock correction cannot establish freshness.
        isStale = age.map { $0 < -1 || $0 > monitor.staleAfter } ?? false
        let offline = isNetworkOffline && !monitor.usesLoopbackConnection
        showsPreviousValue = runtime.lastValue != nil && (
            !monitor.isEnabled || isStale || offline || runtime.consecutiveFailures > 0
        )
        if !monitor.isEnabled { phase = .disabled }
        else if offline { phase = .offline }
        else if isRefreshing { phase = .refreshing }
        else if runtime.consecutiveFailures >= 3 { phase = .failed }
        else if runtime.consecutiveFailures > 0 { phase = .retrying }
        else if isStale { phase = .stale }
        else if runtime.lastSuccessAt != nil { phase = .healthy }
        else { phase = .waiting }
    }

    public var title: String {
        switch phase {
        case .disabled: L10n.string("runtime.disabled")
        case .offline: L10n.string("health.offline")
        case .refreshing: L10n.string("runtime.refreshing")
        case .failed: L10n.string("runtime.repeated_failure")
        case .retrying: L10n.string("health.previous")
        case .stale: L10n.string("health.stale")
        case .healthy: L10n.string("runtime.healthy")
        case .waiting: L10n.string("runtime.awaiting_first_update")
        }
    }

    public var symbol: String {
        switch phase {
        case .disabled: "pause.fill"
        case .offline: "wifi.slash"
        case .refreshing: "arrow.triangle.2.circlepath"
        case .failed, .retrying: "exclamationmark.triangle.fill"
        case .stale, .waiting: "clock"
        case .healthy: "checkmark.circle"
        }
    }

    public var menuBarMarker: String {
        switch phase {
        case .failed, .retrying, .offline: "! "
        case .stale: "◷ "
        case .refreshing: isStale ? "◷ " : ""
        default: ""
        }
    }

    public var detail: String {
        var parts: [String] = []
        if phase == .offline { parts.append(L10n.string("health.offline_detail")) }
        else if let error { parts.append(error.localizedDescription) }
        if isStale, phase != .stale { parts.append(L10n.string("health.stale")) }
        if let lastSuccessAt {
            let formatted = lastSuccessAt.formatted(
                Date.FormatStyle(date: .abbreviated, time: .standard).locale(L10n.locale)
            )
            parts.append(L10n.format("runtime.last_success", formatted))
        } else { parts.append(L10n.string("health.no_success")) }
        return parts.joined(separator: L10n.string("list.detail_separator"))
    }
}

extension Monitor {
    public var staleAfter: TimeInterval {
        2 * Self.normalizedRefreshInterval(refreshInterval) + Self.normalizedRequestTimeout(requestTimeout)
    }

    public var usesLoopbackConnection: Bool {
        guard sourceKind == .prometheus, let host = URL(string: urlString)?.host?.lowercased() else { return false }
        if host == "localhost" || host == "::1" || host == "[::1]" { return true }
        let octets = host.split(separator: ".", omittingEmptySubsequences: false)
        return octets.count == 4 && octets[0] == "127" && octets.allSatisfy { UInt8($0) != nil }
    }
}
