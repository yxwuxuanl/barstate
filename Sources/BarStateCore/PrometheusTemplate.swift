import Foundation

public enum PrometheusTemplateKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case cpu
    case memory
    case disk
    case targetUp

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .cpu: L10n.string("prometheus.template.cpu")
        case .memory: L10n.string("prometheus.template.memory")
        case .disk: L10n.string("prometheus.template.disk")
        case .targetUp: L10n.string("prometheus.template.targetUp")
        }
    }
    public var unit: String { self == .targetUp ? "" : "%" }
}

public struct PrometheusTemplate: Codable, Equatable, Sendable {
    public var kind: PrometheusTemplateKind
    public var job: String
    public var instance: String
    public var mountPoint: String

    public init(
        kind: PrometheusTemplateKind = .cpu,
        job: String = "node",
        instance: String = "",
        mountPoint: String = "/"
    ) {
        self.kind = kind
        self.job = job
        self.instance = instance
        self.mountPoint = mountPoint
    }

    public func query() throws -> String {
        let job = job.trimmingCharacters(in: .whitespacesAndNewlines)
        let instance = instance.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !job.isEmpty, !instance.isEmpty else { throw MonitoringError.prometheusTargetRequired }
        let labels = "job=\(Self.quoted(job)),instance=\(Self.quoted(instance))"
        switch kind {
        case .cpu:
            return "100 * (1 - avg by (job, instance) (rate(node_cpu_seconds_total{\(labels),mode=\"idle\"}[5m])))"
        case .memory:
            return "100 * (1 - node_memory_MemAvailable_bytes{\(labels)} / node_memory_MemTotal_bytes{\(labels)})"
        case .disk:
            guard !mountPoint.isEmpty else { throw MonitoringError.prometheusMountRequired }
            let diskLabels = "\(labels),mountpoint=\(Self.quoted(mountPoint)),fstype!~\"tmpfs|devtmpfs|overlay\""
            let available = "node_filesystem_avail_bytes{\(diskLabels)}"
            let size = "node_filesystem_size_bytes{\(diskLabels)}"
            return "(100 * (1 - \(available) / \(size))) and (\(size) > 0)"
        case .targetUp:
            return "up{\(labels)}"
        }
    }

    private static func quoted(_ text: String) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        // Encoding a String is infallible; JSON and PromQL share quoted-string escapes.
        return String(decoding: try! encoder.encode(text), as: UTF8.self)
    }
}
