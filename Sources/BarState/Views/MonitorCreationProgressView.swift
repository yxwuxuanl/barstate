import BarStateCore
import SwiftUI

struct MonitorCreationProgressView: View {
    let sourceKind: MonitorSourceKind
    let connectionComplete: Bool
    let extractionComplete: Bool
    let displayComplete: Bool

    var body: some View {
        HStack(spacing: 10) {
            stage(
                title: L10n.string("editor.stage_connect"),
                isComplete: connectionComplete,
                isCurrent: !connectionComplete
            )
            connector(isComplete: connectionComplete)
            stage(
                title: sourceKind == .prometheus
                    ? L10n.string("editor.stage_query")
                    : L10n.string("editor.stage_extract"),
                isComplete: extractionComplete,
                isCurrent: connectionComplete && !extractionComplete
            )
            connector(isComplete: extractionComplete)
            stage(
                title: L10n.string("editor.stage_display"),
                isComplete: displayComplete,
                isCurrent: extractionComplete && !displayComplete
            )
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(.background.secondary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.separator.opacity(0.7), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private func stage(title: String, isComplete: Bool, isCurrent: Bool) -> some View {
        HStack(spacing: 7) {
            Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isComplete ? Color.green : isCurrent ? Color.accentColor : .secondary)
                .accessibilityHidden(true)
            Text(title)
                .font(.subheadline.weight(isCurrent || isComplete ? .semibold : .regular))
                .foregroundStyle(isCurrent || isComplete ? .primary : .secondary)
        }
        .accessibilityLabel(title)
        .accessibilityValue(
            isComplete
                ? L10n.string("editor.stage_completed")
                : isCurrent
                    ? L10n.string("editor.stage_current")
                    : L10n.string("editor.stage_upcoming")
        )
    }

    private func connector(isComplete: Bool) -> some View {
        Rectangle()
            .fill(isComplete ? Color.green.opacity(0.7) : Color.secondary.opacity(0.25))
            .frame(width: 34, height: 1)
            .accessibilityHidden(true)
    }
}
