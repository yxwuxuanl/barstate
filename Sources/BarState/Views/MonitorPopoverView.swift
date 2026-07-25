import BarStateCore
import SwiftUI

enum MonitorPopoverMetrics {
    static let width: CGFloat = 440
    static let rowHeight: CGFloat = 92
    static let emptyHeight: CGFloat = 170
    static let baseHeight: CGFloat = 106

    static func listHeight(for monitorCount: Int) -> CGFloat {
        guard monitorCount > 0 else { return emptyHeight }
        let visibleRows = min(monitorCount, 5)
        return CGFloat(visibleRows) * rowHeight + CGFloat(max(visibleRows - 1, 0))
    }
}

struct MonitorPopoverView: View {
    @ObservedObject var store: MonitorStore
    let onRefreshAll: () -> Void
    let onOpenSettings: (UUID?) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            if let persistenceMessage = store.persistenceMessage {
                persistenceBanner(persistenceMessage)
            }

            Divider()

            monitorList

            Divider()

            footer
        }
        .frame(width: MonitorPopoverMetrics.width)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("BarState")
                    .font(.headline)
                Text(L10n.string("popover.subtitle"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onRefreshAll) {
                HStack(spacing: 7) {
                    if store.pollingStatus.isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(refreshButtonText)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(store.pollingStatus.isRefreshing || !hasEnabledMonitors)
            .help(refreshHelpText)
            .accessibilityLabel(refreshButtonText)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
    }

    private var monitorList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if store.orderedMonitors.isEmpty {
                    ContentUnavailableView {
                        Label(
                            L10n.string("popover.empty_title"),
                            systemImage: "waveform.path.ecg"
                        )
                    } description: {
                        Text(L10n.string("popover.empty_description"))
                    } actions: {
                        Button(L10n.string("popover.open_settings")) {
                            onOpenSettings(nil)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: MonitorPopoverMetrics.emptyHeight)
                } else {
                    ForEach(Array(store.orderedMonitors.enumerated()), id: \.element.id) { index, monitor in
                        MonitorPopoverRow(
                            monitor: monitor,
                            isRefreshing: store.pollingStatus.refreshingIDs.contains(monitor.id)
                        ) {
                            onOpenSettings(monitor.id)
                        }

                        if index < store.orderedMonitors.count - 1 {
                            Divider()
                                .padding(.leading, 28)
                        }
                    }
                }
            }
        }
        .frame(height: MonitorPopoverMetrics.listHeight(for: store.orderedMonitors.count))
    }

    private var footer: some View {
        HStack(spacing: 16) {
            if !store.orderedMonitors.isEmpty {
                Button(L10n.string("popover.settings")) {
                    onOpenSettings(nil)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(L10n.string("popover.settings_help"))
            }

            Spacer()

            Menu {
                Button(L10n.string("menu.quit")) {
                    NSApplication.shared.terminate(nil)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(L10n.string("popover.more_actions"))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(L10n.string("popover.more_actions"))
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 12)
    }

    private var hasEnabledMonitors: Bool {
        store.orderedMonitors.contains(where: \.isEnabled)
    }

    private var refreshButtonText: String {
        if store.pollingStatus.isRefreshing {
            return L10n.plural(
                "popover.refreshing_count",
                count: store.pollingStatus.refreshingIDs.count
            )
        }
        if let refreshFeedback = store.refreshFeedback {
            return refreshFeedback
        }
        if !hasEnabledMonitors {
            return L10n.string("popover.no_refreshable_items")
        }
        if store.orderedMonitors.contains(where: { !$0.isEnabled }) {
            return L10n.string("popover.refresh_enabled")
        }
        return L10n.string("popover.refresh_all")
    }

    private var refreshHelpText: String {
        if store.pollingStatus.isRefreshing {
            return L10n.string("popover.refresh_in_progress")
        }
        if !hasEnabledMonitors {
            return L10n.string("popover.enable_monitor_first")
        }
        return L10n.string("popover.refresh_help")
    }

    private func persistenceBanner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.orange)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.vertical, 10)
            .background(Color.orange.opacity(0.08))
            .accessibilityLabel(L10n.format("popover.save_warning", message))
    }
}

private struct MonitorPopoverRow: View {
    let monitor: Monitor
    let isRefreshing: Bool
    let onOpenSettings: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onOpenSettings) {
            HStack(alignment: .center, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(monitor.name)
                        .font(.headline)
                        .foregroundStyle(monitor.isEnabled ? Color.primary : Color.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(monitor.name)

                    Text(statusPrimaryText)
                        .font(.caption)
                        .foregroundStyle(statusColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(statusHelpText)

                    if let statusSecondaryText {
                        Text(statusSecondaryText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(monitor.displayText)
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .foregroundStyle(valueColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                        .help(L10n.format("popover.display_value", monitor.displayText))

                    if showsStaleValue {
                        Text(L10n.string("popover.previous_value"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 150, alignment: .trailing)
            }
            .padding(.horizontal, 28)
            .frame(
                maxWidth: .infinity,
                minHeight: MonitorPopoverMetrics.rowHeight,
                maxHeight: MonitorPopoverMetrics.rowHeight
            )
            .contentShape(Rectangle())
            .background(isHovering ? Color.primary.opacity(0.045) : Color.clear)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(L10n.string("popover.open_monitor_settings"))
    }

    private var statusPrimaryText: String {
        if !monitor.isEnabled {
            return L10n.string("popover.disabled")
        }
        if isRefreshing {
            return L10n.string("popover.refreshing")
        }
        if monitor.runtime.consecutiveFailures == 0 {
            guard let lastSuccessAt = monitor.runtime.lastSuccessAt else {
                return L10n.string("popover.awaiting_first_refresh")
            }
            return successText(for: lastSuccessAt)
        }

        let error = monitor.runtime.lastError?.localizedDescription
            ?? L10n.string("popover.unknown_error")
        if monitor.runtime.consecutiveFailures < failureLimit {
            return L10n.format(
                "popover.update_failed",
                Int64(monitor.runtime.consecutiveFailures),
                Int64(failureLimit),
                error
            )
        }
        return L10n.format("popover.repeated_failure", error)
    }

    private var statusSecondaryText: String? {
        if !monitor.isEnabled {
            guard let lastSuccessAt = monitor.runtime.lastSuccessAt else { return nil }
            return L10n.format(
                "popover.last_success",
                relativeTimeText(for: lastSuccessAt)
            )
        }
        if isRefreshing || monitor.runtime.consecutiveFailures > 0 {
            guard let lastAttemptAt = monitor.runtime.lastAttemptAt else { return nil }
            return L10n.format(
                "popover.last_attempt",
                relativeTimeText(for: lastAttemptAt)
            )
        }
        return nil
    }

    private var showsStaleValue: Bool {
        guard monitor.runtime.lastValue != nil, monitor.runtime.displayValue != nil else { return false }
        return !monitor.isEnabled || monitor.runtime.consecutiveFailures > 0
    }

    private var valueColor: Color {
        showsStaleValue || !monitor.isEnabled ? .secondary : .primary
    }

    private var statusColor: Color {
        if !monitor.isEnabled {
            return .secondary
        }
        if isRefreshing {
            return .secondary
        }
        if monitor.runtime.consecutiveFailures >= failureLimit {
            return .red
        }
        if monitor.runtime.consecutiveFailures > 0 {
            return .orange
        }
        return .secondary
    }

    private var failureLimit: Int { 3 }

    private var statusHelpText: String {
        [statusPrimaryText, statusSecondaryText]
            .compactMap { $0 }
            .joined(separator: L10n.string("list.inline_separator"))
    }

    private var accessibilityLabel: String {
        var components = [monitor.name, monitor.displayText, statusPrimaryText]
        if let statusSecondaryText {
            components.append(statusSecondaryText)
        }
        if showsStaleValue {
            components.append(L10n.string("popover.showing_previous_value"))
        }
        return components.joined(separator: L10n.string("list.accessibility_separator"))
    }

    private func successText(for date: Date) -> String {
        if Date().timeIntervalSince(date) < 60 {
            return L10n.string("popover.updated_just_now")
        }
        return L10n.format("popover.updated_relative", relativeTimeText(for: date))
    }

    private func relativeTimeText(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .full
        formatter.locale = L10n.locale
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
