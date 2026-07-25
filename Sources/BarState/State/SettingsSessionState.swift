import Combine
import Foundation

@MainActor
final class SettingsSessionState: ObservableObject {
    @Published private(set) var isDirty = false
    @Published private(set) var discardGeneration = UUID()
    @Published private(set) var selectionGeneration = UUID()
    private(set) var requestedMonitorID: UUID?

    func setDirty(_ dirty: Bool) {
        isDirty = dirty
    }

    func discardChanges() {
        isDirty = false
        discardGeneration = UUID()
    }

    func requestSelection(_ monitorID: UUID) {
        requestedMonitorID = monitorID
        selectionGeneration = UUID()
    }
}
