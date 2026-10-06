import Foundation

public enum EntryStatus: String, Codable, Sendable { case pending, recorded }
public enum AppAppearance: String, Codable, CaseIterable, Sendable { case system, light, dark }

public enum AppLanguage: String, Codable, CaseIterable, Sendable {
    case system, chinese, english

    public var usesChinese: Bool {
        self == .chinese || (self == .system && (Locale.preferredLanguages.first ?? "").hasPrefix("zh"))
    }
}

public struct JournalEntry: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var start: Date
    public var end: Date
    public var text: String
    public var status: EntryStatus
    public var createdAt: Date
    public var isPending: Bool { status == .pending }
    public var duration: TimeInterval { end.timeIntervalSince(start) }

    public init(id: UUID = UUID(), start: Date, end: Date, text: String = "", status: EntryStatus = .pending, createdAt: Date = Date()) {
        self.id = id
        self.start = start
        self.end = end
        self.text = text
        self.status = status
        self.createdAt = createdAt
    }
}

public struct Preferences: Codable, Equatable, Sendable {
    public var intervalMinutes = 30
    public var playSound = true
    public var appearance: AppAppearance = .system
    public var language: AppLanguage = .system
    public var completedOnboarding = false
    public init() {}
}

public struct RecordingSession: Codable, Equatable, Sendable {
    public var startedAt: Date
    public var segmentStartedAt: Date
    public var lastHeartbeatAt: Date
    public var intervalMinutes: Int

    public init(startedAt: Date, segmentStartedAt: Date, lastHeartbeatAt: Date, intervalMinutes: Int) {
        self.startedAt = startedAt
        self.segmentStartedAt = segmentStartedAt
        self.lastHeartbeatAt = lastHeartbeatAt
        self.intervalMinutes = intervalMinutes
    }
}

public enum JournalError: LocalizedError, Equatable {
    case unsupportedVersion(Int)
    case invalidInterval
    case invalidDates
    case emptyNote
    case duplicateID
    case overlappingEntries
    case activeSessionConflict
    case entryNotFound
    case noBackup

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version): return "This journal uses unsupported version \(version)."
        case .invalidInterval: return "The reminder interval must be between 1 and 240 minutes."
        case .invalidDates: return "The time range is invalid. Its end must be after its start."
        case .emptyNote: return "Write something before saving this entry."
        case .duplicateID: return "The journal contains duplicate entry identifiers."
        case .overlappingEntries: return "This time range overlaps another entry."
        case .activeSessionConflict: return "This time range overlaps the interval currently being recorded."
        case .entryNotFound: return "This entry no longer exists."
        case .noBackup: return "There is no saved backup to restore."
        }
    }
}

public struct JournalState: Codable, Equatable, Sendable {
    public var version = 1
    public var entries: [JournalEntry] = []
    public var preferences = Preferences()
    public var session: RecordingSession?
    public var isRecording: Bool { session != nil }
    public init() {}

    @discardableResult
    public mutating func start(at date: Date) -> Bool {
        guard session == nil, Self.isFinite(date), (1...240).contains(preferences.intervalMinutes),
              !entries.contains(where: { $0.end > date }) else { return false }
        session = RecordingSession(startedAt: date, segmentStartedAt: date, lastHeartbeatAt: date, intervalMinutes: preferences.intervalMinutes)
        return true
    }

    @discardableResult
    public mutating func advance(to date: Date) -> [UUID] {
        guard var current = session, Self.isFinite(date), (1...240).contains(current.intervalMinutes) else { return [] }
        let interval = TimeInterval(current.intervalMinutes * 60)
        var ids: [UUID] = []
        while current.segmentStartedAt.addingTimeInterval(interval) <= date {
            let end = current.segmentStartedAt.addingTimeInterval(interval)
            let entry = JournalEntry(start: current.segmentStartedAt, end: end, createdAt: date)
            entries.append(entry)
            ids.append(entry.id)
            current.segmentStartedAt = end
        }
        current.lastHeartbeatAt = max(current.lastHeartbeatAt, date)
        session = current
        return ids
    }

    @discardableResult
    public mutating func stop(at date: Date) -> [UUID] {
        guard Self.isFinite(date), session != nil else { return [] }
        var ids = advance(to: date)
        if let current = session, date > current.segmentStartedAt {
            let entry = JournalEntry(start: current.segmentStartedAt, end: date, createdAt: date)
            entries.append(entry)
            ids.append(entry.id)
        }
        session = nil
        return ids
    }

    @discardableResult
    public mutating func recoverInterruptedSession() -> [UUID] {
        guard let heartbeat = session?.lastHeartbeatAt else { return [] }
        return stop(at: heartbeat)
    }

    public mutating func setDraft(id: UUID, text: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].text = text
        entries[index].status = .pending
    }

    public mutating func updateEntry(id: UUID, text: String, start: Date? = nil, end: Date? = nil, markRecorded: Bool = true) throws {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { throw JournalError.entryNotFound }
        let newStart = start ?? entries[index].start
        let newEnd = end ?? entries[index].end
        try checkRange(start: newStart, end: newEnd, excluding: id)
        let note = markRecorded ? text.trimmingCharacters(in: .whitespacesAndNewlines) : text
        if markRecorded && note.isEmpty { throw JournalError.emptyNote }
        entries[index].start = newStart
        entries[index].end = newEnd
        entries[index].text = note
        entries[index].status = markRecorded ? .recorded : .pending
    }

    @discardableResult
    public mutating func insertEntry(start: Date, end: Date, text: String) throws -> UUID {
        try checkRange(start: start, end: end)
        let note = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !note.isEmpty else { throw JournalError.emptyNote }
        let entry = JournalEntry(start: start, end: end, text: note, status: .recorded)
        entries.append(entry)
        return entry.id
    }

    public mutating func deleteEntry(id: UUID) {
        entries.removeAll { $0.id == id }
    }

    public func validate() throws {
        guard version == 1 else { throw JournalError.unsupportedVersion(version) }
        guard (1...240).contains(preferences.intervalMinutes) else { throw JournalError.invalidInterval }
        guard Set(entries.map(\.id)).count == entries.count else { throw JournalError.duplicateID }
        let sorted = entries.sorted { $0.start < $1.start }
        for (index, entry) in sorted.enumerated() {
            guard Self.isFinite(entry.start), Self.isFinite(entry.end), Self.isFinite(entry.createdAt), entry.start < entry.end else { throw JournalError.invalidDates }
            if entry.status == .recorded && entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw JournalError.emptyNote }
            if index > 0 && sorted[index - 1].end > entry.start { throw JournalError.overlappingEntries }
        }
        if let current = session {
            guard (1...240).contains(current.intervalMinutes) else { throw JournalError.invalidInterval }
            guard Self.isFinite(current.startedAt), Self.isFinite(current.segmentStartedAt), Self.isFinite(current.lastHeartbeatAt),
                  current.startedAt <= current.segmentStartedAt, current.segmentStartedAt <= current.lastHeartbeatAt else { throw JournalError.invalidDates }
            if entries.contains(where: { $0.end > current.segmentStartedAt }) { throw JournalError.activeSessionConflict }
        }
    }

    private func checkRange(start: Date, end: Date, excluding id: UUID? = nil) throws {
        guard Self.isFinite(start), Self.isFinite(end), start < end else { throw JournalError.invalidDates }
        if entries.contains(where: { $0.id != id && start < $0.end && end > $0.start }) { throw JournalError.overlappingEntries }
        if let current = session, end > current.segmentStartedAt { throw JournalError.activeSessionConflict }
    }

    private static func isFinite(_ date: Date) -> Bool { date.timeIntervalSinceReferenceDate.isFinite }
}
