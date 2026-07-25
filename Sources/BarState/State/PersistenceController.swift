import BarStateCore
import Foundation

struct PersistenceLoadResult: Sendable {
    let state: StoredState
    let warning: String?
}

struct PersistenceController: Sendable {
    let fileURL: URL
    let backupFileURL: URL

    init(fileManager: FileManager = .default) {
        let applicationSupport = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory
        let directory = applicationSupport.appendingPathComponent("BarState", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        self.init(directoryURL: directory)
    }

    init(directoryURL: URL) {
        fileURL = directoryURL.appendingPathComponent("state.json")
        backupFileURL = directoryURL.appendingPathComponent("state.backup.json")
    }

    func load() -> PersistenceLoadResult {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else {
            if fileManager.fileExists(atPath: backupFileURL.path),
               let recovered = try? decodeState(at: backupFileURL)
            {
                try? Self.restrictPermissions(of: backupFileURL)
                return PersistenceLoadResult(
                    state: recovered,
                    warning: L10n.string("persistence.recovered_missing")
                )
            }
            return PersistenceLoadResult(state: StoredState(monitors: []), warning: nil)
        }

        do {
            let state = try decodeState(at: fileURL)
            try? Self.restrictPermissions(of: fileURL)
            if fileManager.fileExists(atPath: backupFileURL.path) {
                try? Self.restrictPermissions(of: backupFileURL)
            }
            return PersistenceLoadResult(state: state, warning: nil)
        } catch {
            do {
                let recovered = try decodeState(at: backupFileURL)
                return PersistenceLoadResult(
                    state: recovered,
                    warning: L10n.string("persistence.recovered_unreadable")
                )
            } catch {
                return PersistenceLoadResult(
                    state: StoredState(monitors: []),
                    warning: L10n.string("persistence.unreadable")
                )
            }
        }
    }

    func save(monitors: [Monitor]) throws {
        let fileManager = FileManager.default
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let data = try JSONEncoder.barState.encode(StoredState(monitors: monitors))
        try data.write(to: fileURL, options: .atomic)
        try Self.restrictPermissions(of: fileURL)
        try data.write(to: backupFileURL, options: .atomic)
        try Self.restrictPermissions(of: backupFileURL)
    }

    private func decodeState(at url: URL) throws -> StoredState {
        let data = try Data(contentsOf: url)
        let state = try JSONDecoder.barState.decode(StoredState.self, from: data)
        guard state.schemaVersion == 1 else {
            throw PersistenceError.unsupportedSchema(state.schemaVersion)
        }
        return state
    }

    private static func restrictPermissions(of url: URL) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: url.path
        )
    }
}

actor PersistenceWriter {
    let persistence: PersistenceController
    private var latestRevision = 0

    init(persistence: PersistenceController) {
        self.persistence = persistence
    }

    func save(monitors: [Monitor], revision: Int) throws -> Bool {
        guard revision >= latestRevision else { return false }
        latestRevision = revision
        try persistence.save(monitors: monitors)
        return true
    }
}

private enum PersistenceError: LocalizedError {
    case unsupportedSchema(Int)

    var errorDescription: String? {
        switch self {
        case let .unsupportedSchema(version):
            L10n.format("persistence.unsupported_version", Int64(version))
        }
    }
}

private extension JSONEncoder {
    static var barState: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var barState: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
