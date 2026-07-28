import BarStateCore
import Foundation

enum PersistenceRecoveryMode: Equatable, Sendable {
    case recoveredFromBackup(primaryWasMissing: Bool)
    case unreadableFiles
}

struct PersistenceLoadResult: Sendable {
    let state: StoredState
    let warning: String?
    let recoveryMode: PersistenceRecoveryMode?
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

    var directoryURL: URL {
        fileURL.deletingLastPathComponent()
    }

    func load() -> PersistenceLoadResult {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else {
            guard fileManager.fileExists(atPath: backupFileURL.path) else {
                return PersistenceLoadResult(
                    state: StoredState(monitors: []),
                    warning: nil,
                    recoveryMode: nil
                )
            }
            if let recovered = try? decodeState(at: backupFileURL) {
                try? Self.restrictPermissions(of: backupFileURL)
                return PersistenceLoadResult(
                    state: recovered,
                    warning: L10n.string("persistence.recovered_missing"),
                    recoveryMode: .recoveredFromBackup(primaryWasMissing: true)
                )
            }
            return PersistenceLoadResult(
                state: StoredState(monitors: []),
                warning: L10n.string("persistence.unreadable"),
                recoveryMode: .unreadableFiles
            )
        }

        do {
            let state = try decodeState(at: fileURL)
            try? Self.restrictPermissions(of: fileURL)
            if fileManager.fileExists(atPath: backupFileURL.path) {
                try? Self.restrictPermissions(of: backupFileURL)
            }
            return PersistenceLoadResult(
                state: state,
                warning: nil,
                recoveryMode: nil
            )
        } catch {
            do {
                let recovered = try decodeState(at: backupFileURL)
                return PersistenceLoadResult(
                    state: recovered,
                    warning: L10n.string("persistence.recovered_unreadable"),
                    recoveryMode: .recoveredFromBackup(primaryWasMissing: false)
                )
            } catch {
                return PersistenceLoadResult(
                    state: StoredState(monitors: []),
                    warning: L10n.string("persistence.unreadable"),
                    recoveryMode: .unreadableFiles
                )
            }
        }
    }

    func save(monitors: [Monitor]) throws {
        try save(state: StoredState(monitors: monitors))
    }

    func save(state: StoredState) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let data = try JSONEncoder.barState.encode(state)
        try data.write(to: fileURL, options: .atomic)
        try Self.restrictPermissions(of: fileURL)
        try data.write(to: backupFileURL, options: .atomic)
        try Self.restrictPermissions(of: backupFileURL)
    }

    @discardableResult
    func resolveRecovery(
        state: StoredState,
        mode: PersistenceRecoveryMode
    ) throws -> [URL] {
        switch mode {
        case .recoveredFromBackup:
            let archived = try archiveExistingFiles([fileURL])
            try save(state: state)
            return archived
        case .unreadableFiles:
            let archived = try archiveExistingFiles([fileURL, backupFileURL])
            try save(state: state)
            return archived
        }
    }

    func export(state: StoredState, to destinationURL: URL) throws {
        let data = try JSONEncoder.barState.encode(state)
        try data.write(to: destinationURL, options: .atomic)
        try Self.restrictPermissions(of: destinationURL)
    }

    private func decodeState(at url: URL) throws -> StoredState {
        let data = try Data(contentsOf: url)
        let state = try JSONDecoder.barState.decode(StoredState.self, from: data)
        guard state.schemaVersion == 1 else {
            throw PersistenceError.unsupportedSchema(state.schemaVersion)
        }
        return state
    }

    private func archiveExistingFiles(_ urls: [URL]) throws -> [URL] {
        let fileManager = FileManager.default
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let timestamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")

        var archived: [URL] = []
        for sourceURL in urls where fileManager.fileExists(atPath: sourceURL.path) {
            let baseName = sourceURL.deletingPathExtension().lastPathComponent
            let candidate = sourceURL.deletingLastPathComponent().appendingPathComponent(
                "\(baseName).corrupt-\(timestamp).json"
            )
            let destination = Self.uniqueArchiveURL(candidate, fileManager: fileManager)
            try fileManager.moveItem(at: sourceURL, to: destination)
            try? Self.restrictPermissions(of: destination)
            archived.append(destination)
        }
        return archived
    }

    private static func uniqueArchiveURL(_ candidate: URL, fileManager: FileManager) -> URL {
        guard fileManager.fileExists(atPath: candidate.path) else { return candidate }
        let stem = candidate.deletingPathExtension().lastPathComponent
        let directory = candidate.deletingLastPathComponent()
        var suffix = 2
        while true {
            let url = directory.appendingPathComponent("\(stem)-\(suffix).json")
            if !fileManager.fileExists(atPath: url.path) { return url }
            suffix += 1
        }
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

    func save(state: StoredState, revision: Int) throws -> Bool {
        guard revision >= latestRevision else { return false }
        latestRevision = revision
        try persistence.save(state: state)
        return true
    }

    func resolveRecovery(
        state: StoredState,
        mode: PersistenceRecoveryMode,
        revision: Int
    ) throws -> [URL] {
        latestRevision = max(latestRevision, revision)
        return try persistence.resolveRecovery(state: state, mode: mode)
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
