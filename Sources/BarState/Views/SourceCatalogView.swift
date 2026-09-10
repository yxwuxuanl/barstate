import BarStateCore
import SwiftUI

enum MonitorSourceChoice: String, CaseIterable, Identifiable {
    case deepSeek, openRouter, siliconFlow, codexQuota, prometheus, httpAPI
    var id: String { rawValue }

    init(monitor: Monitor) {
        if monitor.sourceKind == .httpAPI, let preset = monitor.preset {
            self = switch preset.provider {
            case .deepSeek: .deepSeek
            case .openRouter: .openRouter
            case .siliconFlow: .siliconFlow
            }
        } else {
            self = switch monitor.sourceKind {
            case .httpAPI: .httpAPI
            case .prometheus: .prometheus
            case .codexQuota: .codexQuota
            }
        }
    }

    var provider: DataSourceProvider? {
        switch self {
        case .deepSeek: .deepSeek
        case .openRouter: .openRouter
        case .siliconFlow: .siliconFlow
        default: nil
        }
    }

    var displayName: String {
        if let provider { return provider.displayName }
        return switch self {
        case .codexQuota: "Codex"
        case .prometheus: "Prometheus"
        default: L10n.string("source.custom_http")
        }
    }

    var detail: String {
        switch self {
        case .deepSeek: L10n.string("source.deepseek_hint")
        case .openRouter: L10n.string("source.openrouter_hint")
        case .siliconFlow: L10n.string("source.siliconflow_hint")
        case .codexQuota: L10n.string("source.codex_hint")
        case .prometheus: L10n.string("source.prometheus_hint")
        case .httpAPI: L10n.string("source.http_hint")
        }
    }

    var symbol: String {
        switch self {
        case .codexQuota: "terminal"
        case .prometheus: "server.rack"
        case .httpAPI: "network"
        default: "creditcard"
        }
    }

    func configure(_ monitor: inout Monitor) {
        monitor.preset = provider.map { DataSourcePreset(provider: $0) }
        monitor.prometheusTemplate = nil
        monitor.authentication = .init()
        monitor.requestHeaders = []
        monitor.parser = .init()
        monitor.promQL = ""
        monitor.runtime = .init()
        if let preset = monitor.preset {
            monitor.sourceKind = .httpAPI
            monitor.urlString = preset.provider.endpoint
            monitor.displayTemplate = preset.defaultDisplayTemplate
            monitor.refreshInterval = 300
            monitor.refreshIntervalUnit = .minutes
        } else if self == .codexQuota {
            monitor.sourceKind = .codexQuota
            monitor.urlString = CodexQuota.endpointURLString
            monitor.displayTemplate = L10n.string("monitor.codex_quota_template")
            monitor.refreshInterval = 300
            monitor.refreshIntervalUnit = .minutes
        } else {
            monitor.sourceKind = self == .prometheus ? .prometheus : .httpAPI
            monitor.urlString = "https://"
            monitor.displayTemplate = Monitor.valuePlaceholder
            monitor.refreshInterval = 60
            monitor.refreshIntervalUnit = .seconds
        }
    }

    func makeMonitor(order: Int) -> Monitor {
        var monitor = Monitor.draft(order: order)
        configure(&monitor)
        if self != .httpAPI { monitor.name = displayName }
        if self == .prometheus {
            monitor.prometheusTemplate = PrometheusTemplate()
            monitor.displayTemplate = "CPU \(Monitor.valuePlaceholder)%"
        }
        return monitor
    }
}

struct SourceCatalogView: View {
    let onSelect: (MonitorSourceChoice) -> Void
    let onExample: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.string("source.catalog_title")).font(.title2.weight(.semibold))
                Text(L10n.string("source.catalog_hint")).foregroundStyle(.secondary)
            }
            .padding(24)
            List {
                Section(L10n.string("source.group.ai")) {
                    ForEach([MonitorSourceChoice.deepSeek, .openRouter, .siliconFlow, .codexQuota]) { row($0) }
                }
                Section(L10n.string("source.group.server")) { row(.prometheus) }
                Section(L10n.string("source.group.custom")) { row(.httpAPI) }
            }
            .listStyle(.inset)
            Divider()
            HStack {
                Button(L10n.string("settings.add_template"), action: onExample)
                    .buttonStyle(.link)
                Spacer()
                Button(L10n.string("common.cancel"), action: onCancel)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(20)
        }
        .frame(width: 500, height: 560)
    }

    private func row(_ choice: MonitorSourceChoice) -> some View {
        Button { onSelect(choice) } label: {
            HStack(spacing: 12) {
                Image(systemName: choice.symbol)
                    .font(.system(size: 18)).foregroundStyle(.secondary)
                    .frame(width: 26).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(choice.displayName).font(.body.weight(.medium))
                    Text(choice.detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
