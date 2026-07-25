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
