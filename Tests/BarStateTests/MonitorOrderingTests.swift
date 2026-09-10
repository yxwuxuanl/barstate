import BarStateCore
import Foundation
import Testing
@testable import BarState

@MainActor
struct MonitorOrderingTests {
    private func monitors() -> [Monitor] {
        ["A", "B", "C", "D"].enumerated().map { index, name in
            Monitor(name: name, order: index)
        }
    }

    @Test func moveActionUpdatesOrderAndConfigurationCallback() {
        let original = monitors()
        let store = MonitorStore(initialMonitors: original)
        var notifiedOrder: [UUID] = []
        store.onConfigurationChange = { notifiedOrder = $0.map(\.id) }

        store.move(id: original[3].id, offset: -1)

        let expected = [original[0], original[1], original[3], original[2]].map(\.id)
        #expect(store.orderedMonitors.map(\.id) == expected)
        #expect(notifiedOrder == expected)
        #expect(store.orderedMonitors.map(\.order) == [0, 1, 2, 3])
        store.move(id: original[0].id, offset: -1)
        #expect(store.orderedMonitors.map(\.id) == expected)
    }

    @Test func dragReorderSurvivesPersistenceRoundTrip() throws {
        let original = monitors()
        let store = MonitorStore(initialMonitors: original)

        store.move(fromOffsets: IndexSet([0, 2]), toOffset: 4)

        let expected = [original[1], original[3], original[0], original[2]].map(\.id)
        #expect(store.orderedMonitors.map(\.id) == expected)
        let saved = try JSONEncoder().encode(StoredState(monitors: store.orderedMonitors))
        let decoded = try JSONDecoder().decode(StoredState.self, from: saved)
        let reloaded = MonitorStore(initialMonitors: decoded.monitors)
        #expect(reloaded.orderedMonitors.map(\.id) == expected)
    }

    @Test func savingAnOlderDraftPreservesCurrentOrder() {
        let original = monitors()
        let store = MonitorStore(initialMonitors: original)
        var draft = original[3]
        draft.name = "Renamed D"
        store.move(id: draft.id, offset: -3)

        store.update(draft)

        #expect(store.orderedMonitors.map(\.id) == [original[3], original[0], original[1], original[2]].map(\.id))
        #expect(store.monitor(id: draft.id)?.name == "Renamed D")
    }
}
