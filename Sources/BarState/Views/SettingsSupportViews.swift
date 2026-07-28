import AppKit
import BarStateCore
import SwiftUI

struct FirstMonitorWelcomeView: View {
    let onCreateHTTP: () -> Void
    let onCreatePrometheus: () -> Void
    let onUseJSONTemplate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "waveform.path.ecg.rectangle")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text(L10n.string("onboarding.title"))
                    .font(.system(size: 30, weight: .semibold))
                Text(L10n.string("onboarding.description"))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(L10n.string("onboarding.steps"))
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }

            VStack(spacing: 0) {
                onboardingAction(
                    title: L10n.string("onboarding.http_title"),
                    detail: L10n.string("onboarding.http_description"),
                    systemImage: "network",
                    isPrimary: true,
                    action: onCreateHTTP
                )
                Divider().padding(.leading, 52)
                onboardingAction(
                    title: L10n.string("onboarding.prometheus_title"),
                    detail: L10n.string("onboarding.prometheus_description"),
                    systemImage: "chart.xyaxis.line",
                    action: onCreatePrometheus
                )
                Divider().padding(.leading, 52)
                onboardingAction(
                    title: L10n.string("onboarding.template_title"),
                    detail: L10n.string("onboarding.template_description"),
                    systemImage: "doc.badge.plus",
                    action: onUseJSONTemplate
                )
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.separator.opacity(0.7), lineWidth: 1)
            }
        }
        .frame(maxWidth: 650, alignment: .leading)
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func onboardingAction(
        title: String,
        detail: String,
        systemImage: String,
        isPrimary: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isPrimary ? Color.accentColor : Color.secondary)
                    .frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 16)
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(detail)")
    }
}

struct PersistenceRecoveryBanner: View {
    let mode: PersistenceRecoveryMode
    let isWorking: Bool
    let onRestore: () -> Void
    let onExport: () -> Void
    let onShowFiles: () -> Void
    let onStartFresh: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 16)

            HStack(spacing: 8) {
                Button(L10n.string("recovery.show_files"), action: onShowFiles)
                switch mode {
                case .recoveredFromBackup:
                    Button(L10n.string("recovery.export"), action: onExport)
                    Button(L10n.string("recovery.restore"), action: onRestore)
                        .buttonStyle(.borderedProminent)
                case .unreadableFiles:
                    Button(
                        L10n.string("recovery.start_fresh"),
                        role: .destructive,
                        action: onStartFresh
                    )
                }
            }
            .disabled(isWorking)

            if isWorking {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(L10n.string("runtime.refreshing"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(tint.opacity(0.09))
        .overlay(alignment: .bottom) {
            Divider()
        }
        .accessibilityElement(children: .contain)
    }

    private var title: String {
        switch mode {
        case .recoveredFromBackup: L10n.string("recovery.backup_title")
        case .unreadableFiles: L10n.string("recovery.unreadable_title")
        }
    }

    private var message: String {
        switch mode {
        case .recoveredFromBackup: L10n.string("recovery.backup_message")
        case .unreadableFiles: L10n.string("recovery.unreadable_message")
        }
    }

    private var iconName: String {
        switch mode {
        case .recoveredFromBackup: "externaldrive.badge.checkmark"
        case .unreadableFiles: "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch mode {
        case .recoveredFromBackup: .orange
        case .unreadableFiles: .red
        }
    }
}
