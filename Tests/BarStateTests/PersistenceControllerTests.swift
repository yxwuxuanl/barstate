import BarStateCore
import Foundation
import Testing
@testable import BarState

struct PersistenceControllerTests {
    @Test func recoversFromBackupWhenPrimaryIsCorrupt() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = PersistenceController(directoryURL: directory)
        let monitor = Monitor(name: "saved")

        try persistence.save(monitors: [monitor])
        try Data("not-json".utf8).write(to: persistence.fileURL, options: .atomic)

        let loaded = persistence.load()
        #expect(loaded.state.monitors == [monitor])
        #expect(loaded.warning != nil)
        #expect(loaded.recoveryMode == .recoveredFromBackup(primaryWasMissing: false))

        let archived = try persistence.resolveRecovery(
            state: loaded.state,
            mode: try #require(loaded.recoveryMode)
        )
        #expect(archived.count == 1)
        #expect(persistence.load().state.monitors == [monitor])
        #expect(persistence.load().recoveryMode == nil)
    }

    @Test func recoversFromBackupWhenPrimaryIsMissing() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = PersistenceController(directoryURL: directory)
        let monitor = Monitor(name: "saved")

        try persistence.save(monitors: [monitor])
        try FileManager.default.removeItem(at: persistence.fileURL)

        let loaded = persistence.load()
        #expect(loaded.state.monitors == [monitor])
        #expect(loaded.warning != nil)
        #expect(loaded.recoveryMode == .recoveredFromBackup(primaryWasMissing: true))
    }

    @Test @MainActor func unreadableFilesBlockWritesUntilStartingFresh() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = PersistenceController(directoryURL: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("broken-primary".utf8).write(to: persistence.fileURL)
        try Data("broken-backup".utf8).write(to: persistence.backupFileURL)

        let store = MonitorStore(persistence: persistence)
        #expect(store.recoveryMode == .unreadableFiles)
        #expect(store.isPersistenceWriteProtected)

        store.add(Monitor(name: "must-not-overwrite"))
        #expect(store.monitors.isEmpty)
        let primaryContents = String(
            decoding: try Data(contentsOf: persistence.fileURL),
            as: UTF8.self
        )
        #expect(primaryContents == "broken-primary")

        await store.startFreshAfterRecovery()

        #expect(store.recoveryMode == nil)
        #expect(!store.isPersistenceWriteProtected)
        #expect(persistence.load().state.monitors.isEmpty)
        let archivedFiles = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.contains(".corrupt-") }
        #expect(archivedFiles.count == 2)
    }

    @Test func persistsMenuBarPreferencesAndLoadsLegacyDefaults() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = PersistenceController(directoryURL: directory)
        let preferences = AppPreferences(
            menuBarPresentation: .compact,
            menuBarMaximumCharacters: 18
        )

        try persistence.save(
            state: StoredState(monitors: [Monitor(name: "saved")], preferences: preferences)
        )

        #expect(persistence.load().state.preferences == preferences)

        var legacyObject = try JSONSerialization.jsonObject(
            with: Data(contentsOf: persistence.fileURL)
        ) as! [String: Any]
        legacyObject.removeValue(forKey: "preferences")
        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
        try legacyData.write(to: persistence.fileURL, options: .atomic)
        try legacyData.write(to: persistence.backupFileURL, options: .atomic)

        #expect(persistence.load().state.preferences == AppPreferences())
    }

    @Test func savedFilesAreReadableOnlyByCurrentUser() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = PersistenceController(directoryURL: directory)

        try persistence.save(monitors: [Monitor(name: "private")])

        for url in [persistence.fileURL, persistence.backupFileURL] {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let permissions = attributes[.posixPermissions] as? NSNumber
            #expect(permissions?.intValue == 0o600)
        }
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("BarStateTests-\(UUID().uuidString)", isDirectory: true)
    }
}
