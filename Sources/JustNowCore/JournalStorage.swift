import Foundation

public final class JournalStorage {
    public let directory: URL
    public let fileURL: URL
    private var backupURL: URL { directory.appendingPathComponent("journal.previous.json") }

    public init(directory: URL) {
        self.directory = directory
        fileURL = directory.appendingPathComponent("journal.json")
    }

    public func load() throws -> JournalState {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return JournalState() }
        return try read(fileURL)
    }

    public func save(_ state: JournalState) throws {
        try state.validate()
        let data = try Self.encoder().encode(state)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            // Validate before replacing either copy; a corrupt primary is never silently reset.
            let previous = try Data(contentsOf: fileURL)
            _ = try decode(previous)
            try previous.write(to: backupURL, options: .atomic)
        }
        try data.write(to: fileURL, options: .atomic)
    }

    public func restoreBackup() throws -> JournalState {
        guard FileManager.default.fileExists(atPath: backupURL.path) else { throw JournalError.noBackup }
        let data = try Data(contentsOf: backupURL)
        let recovered = try decode(data)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let preserved = directory.appendingPathComponent("journal.corrupt-\(UUID().uuidString).json")
            try Data(contentsOf: fileURL).write(to: preserved, options: .atomic)
        }
        try data.write(to: fileURL, options: .atomic)
        return recovered
    }

    private func read(_ url: URL) throws -> JournalState {
        try decode(Data(contentsOf: url))
    }

    private func decode(_ data: Data) throws -> JournalState {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let state = try decoder.decode(JournalState.self, from: data)
        try state.validate()
        return state
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
