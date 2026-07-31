import AppKit
import BarStateCore
import SwiftUI

extension StatusIndicatorColor {
    var localizedName: String {
        switch self {
        case .red: L10n.string("status_indicator.color.red")
        case .orange: L10n.string("status_indicator.color.orange")
        case .yellow: L10n.string("status_indicator.color.yellow")
        case .green: L10n.string("status_indicator.color.green")
        case .mint: L10n.string("status_indicator.color.mint")
        case .blue: L10n.string("status_indicator.color.blue")
        case .purple: L10n.string("status_indicator.color.purple")
        case .pink: L10n.string("status_indicator.color.pink")
        case .gray: L10n.string("status_indicator.color.gray")
        }
    }

    var nsColor: NSColor {
        switch self {
        case .red: .systemRed
        case .orange: .systemOrange
        case .yellow: .systemYellow
        case .green: .systemGreen
        case .mint: .systemMint
        case .blue: .systemBlue
        case .purple: .systemPurple
        case .pink: .systemPink
        case .gray: .systemGray
        }
    }

    var swiftUIColor: Color { Color(nsColor: nsColor) }

    var menuSwatchImage: NSImage {
        let size = NSSize(width: 12, height: 12)
        let image = NSImage(size: size, flipped: false) { rect in
            let path = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
            nsColor.setFill()
            path.fill()
            NSColor.separatorColor.setStroke()
            path.lineWidth = 0.5
            path.stroke()
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = localizedName
        return image
    }
}

extension StatusIndicatorAppearance {
    var accessibilityText: String {
        switch kind {
        case .matched:
            L10n.format("status_indicator.accessibility_color", color.localizedName)
        case .unavailable:
            L10n.string("status_indicator.accessibility_unavailable")
        case .mixed:
            L10n.string("status_indicator.accessibility_mixed")
        }
    }
}

private struct StatusColorSwatch: View {
    let color: StatusIndicatorColor
    var diameter: CGFloat = 8

    var body: some View {
        Circle()
            .fill(color.swiftUIColor)
            .frame(width: diameter, height: diameter)
            .overlay {
                Circle()
                    .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
            }
            .accessibilityHidden(true)
    }
}

struct StatusIndicatorDot: View {
    let appearance: StatusIndicatorAppearance
    var diameter: CGFloat = 8

    var body: some View {
        StatusColorSwatch(color: appearance.color, diameter: diameter)
            .accessibilityHidden(false)
            .accessibilityLabel(appearance.accessibilityText)
    }
}

struct StatusIndicatorEditorControls: View {
    @Binding var configuration: StatusIndicatorConfiguration

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Text(L10n.string("common.value"))
                    .frame(width: 112, alignment: .leading)
                Text(L10n.string("editor.status_indicator_color"))
                    .frame(width: 132, alignment: .leading)
                Spacer(minLength: 0)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if configuration.rules.isEmpty {
                Text(L10n.string("editor.status_indicator_empty"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(configuration.rules.enumerated()), id: \.element.id) { index, rule in
                StatusIndicatorRuleRow(
                    rule: stableRuleBinding(for: rule),
                    position: index + 1,
                    onDelete: {
                        configuration.rules.removeAll { $0.id == rule.id }
                    }
                )
            }

            Button {
                configuration.rules.append(
                    StatusIndicatorRule(color: suggestedColor)
                )
            } label: {
                Label(L10n.string("editor.status_indicator_add_rule"), systemImage: "plus")
            }
            .buttonStyle(.link)
        }
    }

    private func stableRuleBinding(for rule: StatusIndicatorRule) -> Binding<StatusIndicatorRule> {
        Binding(
            get: {
                configuration.rules.first { $0.id == rule.id } ?? rule
            },
            set: { updatedRule in
                guard let index = configuration.rules.firstIndex(
                    where: { $0.id == rule.id }
                ) else { return }
                var stableRule = updatedRule
                stableRule.id = rule.id
                configuration.rules[index] = stableRule
            }
        )
    }

    private var suggestedColor: StatusIndicatorColor {
        let palette: [StatusIndicatorColor] = [
            .green, .orange, .red, .blue, .purple, .pink, .yellow, .mint, .gray
        ]
        return palette[configuration.rules.count % palette.count]
    }
}

private struct StatusIndicatorRuleRow: View {
    @Binding var rule: StatusIndicatorRule
    let position: Int
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            TextField(
                L10n.string("common.value"),
                value: $rule.value,
                format: .number.precision(.fractionLength(0...6))
            )
            .frame(width: 112)
            .accessibilityLabel(
                L10n.format(
                    "editor.status_indicator_rule_value_accessibility",
                    Int64(position)
                )
            )

            StatusIndicatorColorMenu(selection: $rule.color)
                .frame(width: 132, alignment: .leading)

            Button(action: onDelete) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .frame(width: 28, height: 28)
            .help(L10n.string("editor.status_indicator_delete_rule"))
            .accessibilityLabel(
                L10n.format(
                    "editor.status_indicator_delete_rule_accessibility",
                    Int64(position)
                )
            )

            Spacer(minLength: 0)
        }
    }
}

private struct StatusIndicatorColorMenu: View {
    @Binding var selection: StatusIndicatorColor

    var body: some View {
        StatusIndicatorColorPopUpButton(selection: $selection)
            .frame(width: 124, height: 24)
        .help(L10n.string("editor.status_indicator_choose_color"))
        .accessibilityLabel(
            L10n.format(
                "editor.status_indicator_color_accessibility",
                selection.localizedName
            )
        )
    }
}

private struct StatusIndicatorColorPopUpButton: NSViewRepresentable {
    @Binding var selection: StatusIndicatorColor

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.controlSize = .small
        button.bezelStyle = .inline
        button.isBordered = false
        button.alignment = .left
        button.imagePosition = .imageLeading
        button.imageScaling = .scaleNone
        button.target = context.coordinator
        button.action = #selector(Coordinator.selectionChanged(_:))
        button.menu?.delegate = context.coordinator
        updateMenuItems(in: button, coordinator: context.coordinator)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.selection = $selection
        button.menu?.delegate = context.coordinator
        updateMenuItems(in: button, coordinator: context.coordinator)
        button.selectItem(
            withTitle: selection.localizedName
        )
        button.setAccessibilityLabel(
            L10n.format(
                "editor.status_indicator_color_accessibility",
                selection.localizedName
            )
        )
    }

    private func updateMenuItems(
        in button: NSPopUpButton,
        coordinator: Coordinator
    ) {
        button.removeAllItems()
        for color in StatusIndicatorColor.allCases {
            let item = NSMenuItem(
                title: color.localizedName,
                action: nil,
                keyEquivalent: ""
            )
            item.image = color.menuSwatchImage
            item.representedObject = color.rawValue
            item.view = StatusIndicatorColorMenuItemView(
                color: color,
                isSelected: color == selection
            ) { [weak button, weak coordinator] in
                guard let button, let coordinator else { return }
                coordinator.select(color, in: button)
            }
            button.menu?.addItem(item)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSMenuDelegate {
        var selection: Binding<StatusIndicatorColor>

        init(selection: Binding<StatusIndicatorColor>) {
            self.selection = selection
        }

        @objc func selectionChanged(_ sender: NSPopUpButton) {
            guard let rawValue = sender.selectedItem?.representedObject as? String,
                  let color = StatusIndicatorColor(rawValue: rawValue)
            else { return }
            selection.wrappedValue = color
        }

        func select(_ color: StatusIndicatorColor, in button: NSPopUpButton) {
            button.selectItem(withTitle: color.localizedName)
            selection.wrappedValue = color
            button.menu?.cancelTracking()
        }

        func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
            for menuItem in menu.items {
                guard let itemView = menuItem.view
                    as? StatusIndicatorColorMenuItemView
                else { continue }
                itemView.isHighlighted = menuItem === item
            }
        }

        func menuDidClose(_ menu: NSMenu) {
            for item in menu.items {
                (item.view as? StatusIndicatorColorMenuItemView)?.isHighlighted = false
            }
        }
    }
}

@MainActor
private final class StatusIndicatorColorMenuItemView: NSView {
    var isHighlighted = false {
        didSet { updateAppearance() }
    }

    private let color: StatusIndicatorColor
    private let isSelected: Bool
    private let onSelect: () -> Void
    private let swatchView: StatusIndicatorColorSwatchView
    private let titleLabel: NSTextField
    private let selectionImageView: NSImageView

    init(
        color: StatusIndicatorColor,
        isSelected: Bool,
        onSelect: @escaping () -> Void
    ) {
        self.color = color
        self.isSelected = isSelected
        self.onSelect = onSelect
        swatchView = StatusIndicatorColorSwatchView(color: color.nsColor)
        titleLabel = NSTextField(labelWithString: color.localizedName)
        selectionImageView = NSImageView(
            image: NSImage(
                systemSymbolName: "checkmark",
                accessibilityDescription: nil
            ) ?? NSImage()
        )
        super.init(frame: NSRect(x: 0, y: 0, width: 176, height: 28))

        wantsLayer = true
        layer?.cornerRadius = 5
        autoresizingMask = [.width]

        titleLabel.font = .menuFont(ofSize: 0)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1

        selectionImageView.symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: 11,
            weight: .semibold
        )
        selectionImageView.imageScaling = .scaleProportionallyDown
        selectionImageView.isHidden = !isSelected

        addSubview(swatchView)
        addSubview(titleLabel)
        addSubview(selectionImageView)
        updateAppearance()

        setAccessibilityElement(true)
        setAccessibilityRole(.menuItem)
        setAccessibilityLabel(color.localizedName)
        setAccessibilitySelected(isSelected)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let midY = bounds.midY
        swatchView.frame = NSRect(x: 12, y: midY - 5, width: 10, height: 10)
        selectionImageView.frame = NSRect(
            x: bounds.width - 25,
            y: midY - 7,
            width: 14,
            height: 14
        )
        titleLabel.frame = NSRect(
            x: 32,
            y: midY - 10,
            width: max(0, bounds.width - 65),
            height: 20
        )
    }

    override func mouseUp(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        guard bounds.contains(location) else { return }
        onSelect()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    private func updateAppearance() {
        layer?.backgroundColor = isHighlighted
            ? NSColor.controlAccentColor.cgColor
            : NSColor.clear.cgColor
        let foregroundColor: NSColor = isHighlighted
            ? .alternateSelectedControlTextColor
            : .labelColor
        titleLabel.textColor = foregroundColor
        selectionImageView.contentTintColor = foregroundColor
    }
}

@MainActor
private final class StatusIndicatorColorSwatchView: NSView {
    private let color: NSColor

    init(color: NSColor) {
        self.color = color
        super.init(frame: .zero)
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5))
        color.setFill()
        circle.fill()
        NSColor.separatorColor.setStroke()
        circle.lineWidth = 0.5
        circle.stroke()
    }
}
