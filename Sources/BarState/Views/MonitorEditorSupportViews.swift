import BarStateCore
import Foundation
import SwiftUI

struct MonitorRuntimeStatusView: View {
    let runtime: MonitorRuntimeState
    let isRefreshing: Bool
    let nextRefreshAt: Date?
    let isEnabled: Bool
    let isSavedMonitor: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: iconName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(statusColor)
                .frame(width: 24, height: 24)
                .background(statusColor.opacity(0.12), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .help(detail)
            }

            Spacer(minLength: 12)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator.opacity(0.65), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        if !isSavedMonitor { return L10n.string("runtime.unsaved") }
        if !isEnabled { return L10n.string("runtime.disabled") }
        if isRefreshing { return L10n.string("runtime.refreshing") }
        if runtime.consecutiveFailures >= 3 {
            return L10n.string("runtime.repeated_failure")
        }
        if runtime.consecutiveFailures > 0 {
            return L10n.format(
                "runtime.recent_failure",
                Int64(runtime.consecutiveFailures)
            )
        }
        if runtime.lastSuccessAt != nil { return L10n.string("runtime.healthy") }
        return L10n.string("runtime.awaiting_first_update")
    }

    private var detail: String {
        if !isSavedMonitor {
            return L10n.string("runtime.unsaved_detail")
        }
        if !isEnabled {
            return L10n.string("runtime.disabled_detail")
        }

        var parts: [String] = []
        if let error = runtime.lastError {
            parts.append(error.localizedDescription)
        }
        if runtime.lastError != nil, let lastAttemptAt = runtime.lastAttemptAt {
            parts.append(L10n.format("runtime.last_attempt", dateText(lastAttemptAt)))
        } else if let lastSuccessAt = runtime.lastSuccessAt {
            parts.append(L10n.format("runtime.last_success", dateText(lastSuccessAt)))
        }
        if !isRefreshing, let nextRefreshAt {
            parts.append(L10n.format("runtime.next_refresh", dateText(nextRefreshAt)))
        }
        if parts.isEmpty {
            return L10n.string("runtime.enabled_detail")
        }
        return parts.joined(separator: L10n.string("list.detail_separator"))
    }

    private var iconName: String {
        if !isSavedMonitor { return "square.and.arrow.down" }
        if !isEnabled { return "pause.fill" }
        if isRefreshing { return "arrow.triangle.2.circlepath" }
        if runtime.consecutiveFailures > 0 { return "exclamationmark.triangle.fill" }
        if runtime.lastSuccessAt != nil { return "checkmark.circle.fill" }
        return "clock.fill"
    }

    private var statusColor: Color {
        if !isSavedMonitor || !isEnabled { return .secondary }
        if isRefreshing { return .accentColor }
        if runtime.consecutiveFailures >= 3 { return .red }
        if runtime.consecutiveFailures > 0 { return .orange }
        if runtime.lastSuccessAt != nil { return .green }
        return .secondary
    }

    private func dateText(_ date: Date) -> String {
        date.formatted(
            Date.FormatStyle(date: .abbreviated, time: .shortened)
                .locale(L10n.locale)
        )
    }
}
struct ResponsePreviewView: View {
    let response: HTTPResponseSnapshot?
    let isLoading: Bool
    let isConfigurationStale: Bool
    let sourceLabel: String
    let latestRequestFailure: EditorRequestFailure?
    @State private var showsHTTPDetails = false

    private let panelBackground = Color(red: 0.12, green: 0.13, blue: 0.17)

    var body: some View {
        VStack(spacing: 0) {
            if let latestRequestFailure {
                latestFailureBanner(latestRequestFailure)
            }
            metadataBar

            ScrollView([.horizontal, .vertical]) {
                Text(bodyText)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(response == nil ? 0.55 : 0.92))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(14)
            }
            .frame(minHeight: 132, maxHeight: 210)
            .background(panelBackground)

            DisclosureGroup(isExpanded: $showsHTTPDetails) {
                ScrollView(.horizontal) {
                    Text(
                        response?.fullHTTPDetails
                            ?? L10n.string("response.no_http_details")
                    )
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                }
            } label: {
                HStack(spacing: 14) {
                    Text(L10n.string("response.http_details"))
                        .font(.subheadline.weight(.semibold))
                    Text(
                        response?.detailsSummary
                            ?? L10n.format("response.header_summary.zero", "HTTP")
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.background.secondary.opacity(0.45))
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator.opacity(0.75), lineWidth: 1)
        }
    }

    private func latestFailureBanner(_ failure: EditorRequestFailure) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(
                    response == nil
                        ? L10n.string("response.latest_request_failed")
                        : L10n.string("response.latest_request_failed_preserved")
                )
                    .font(.caption.weight(.semibold))
                Text(failure.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .help(failure.message)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(
                    failure.attemptedAt.formatted(
                        Date.FormatStyle(date: .omitted, time: .shortened)
                            .locale(L10n.locale)
                    )
                )
                if let requestDurationText = requestDurationText(failure.requestDuration) {
                    Text(requestDurationText)
                }
            }
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.09))
        .accessibilityElement(children: .combine)
    }

    private var metadataBar: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(sourceLabel)
                    .font(.subheadline.weight(.semibold))
                if isConfigurationStale {
                    Text(L10n.string("response.configuration_changed"))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Spacer(minLength: 12)
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
                if let statusText = response?.statusText {
                    Text(statusText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(statusColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(
                            statusColor.opacity(0.1),
                            in: RoundedRectangle(cornerRadius: 5)
                        )
                }
            }

            HStack(spacing: 8) {
                Text(responseTimeText)
                    .layoutPriority(2)
                if let requestDurationText = requestDurationText(response?.requestDuration) {
                    Text("·")
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                    Text(requestDurationText)
                        .layoutPriority(1)
                }
                Spacer(minLength: 12)
                Text(response?.contentType ?? L10n.string("response.unknown_type"))
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 280, alignment: .trailing)
                    .help(response?.contentType ?? L10n.string("response.no_content_type"))
            }
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.background.secondary.opacity(0.28))
    }

    private var bodyText: String {
        response?.bodyText ?? L10n.string("response.no_response")
    }

    private var responseTimeText: String {
        guard let date = response?.requestedAt else {
            return L10n.string("response.time_unavailable")
        }
        return L10n.format(
            "response.time",
            date.formatted(
                Date.FormatStyle(date: .numeric, time: .standard)
                    .locale(L10n.locale)
            )
        )
    }

    private func requestDurationText(_ duration: TimeInterval?) -> String? {
        guard let duration, duration.isFinite, duration >= 0 else { return nil }
        if duration < 1 {
            return L10n.format(
                "response.duration_milliseconds",
                Int64((duration * 1_000).rounded())
            )
        }
        return L10n.format("response.duration_seconds", duration)
    }

    private var statusColor: Color {
        guard let statusCode = response?.statusCode else { return .secondary }
        return (200...299).contains(statusCode) ? .green : .red
    }
}
