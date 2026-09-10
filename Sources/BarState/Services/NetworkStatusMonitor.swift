import Foundation
import Network

final class NetworkStatusMonitor: @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.barstate.network-status")
    private let onConnectionRestored: @Sendable () -> Void
    private let onStatusChange: @Sendable (Bool) -> Void
    private var previousStatus: NWPath.Status?

    init(onStatusChange: @escaping @Sendable (Bool) -> Void = { _ in },
         onConnectionRestored: @escaping @Sendable () -> Void) {
        self.onStatusChange = onStatusChange
        self.onConnectionRestored = onConnectionRestored
    }

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let previousStatus = self.previousStatus
            self.previousStatus = path.status
            self.onStatusChange(path.status != .satisfied)
            if let previousStatus,
               previousStatus != .satisfied,
               path.status == .satisfied
            {
                self.onConnectionRestored()
            }
        }
        monitor.start(queue: queue)
    }

    func cancel() {
        monitor.cancel()
    }

    deinit {
        monitor.cancel()
    }
}
