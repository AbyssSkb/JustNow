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
    public var applicationUsage: ApplicationUsageSummary?
    public var isPending: Bool { status == .pending }
    public var duration: TimeInterval { end.timeIntervalSince(start) }

    public init(id: UUID = UUID(), start: Date, end: Date, text: String = "", status: EntryStatus = .pending, createdAt: Date = Date(), applicationUsage: ApplicationUsageSummary? = nil) {
        self.id = id
        self.start = start
        self.end = end
        self.text = text
        self.status = status
        self.createdAt = createdAt
        self.applicationUsage = applicationUsage
    }
}

public struct Preferences: Codable, Equatable, Sendable {
    public var intervalMinutes = 30
    public var playSound = true
    public var appearance: AppAppearance = .system
    public var language: AppLanguage = .system
    public var completedOnboarding = false
    public var captureApplicationUsage: Bool?
    public var autoStartRecording: Bool?
    public var pauseWhenInactive: Bool?
    public init() {}
}

public struct RecordingSession: Codable, Equatable, Sendable {
    public var startedAt: Date
    public var segmentStartedAt: Date
    public var lastHeartbeatAt: Date
    public var intervalMinutes: Int
    public var applicationActivity: [ApplicationActivity]?

    public init(startedAt: Date, segmentStartedAt: Date, lastHeartbeatAt: Date, intervalMinutes: Int, applicationActivity: [ApplicationActivity]? = nil) {
        self.startedAt = startedAt
        self.segmentStartedAt = segmentStartedAt
        self.lastHeartbeatAt = lastHeartbeatAt
        self.intervalMinutes = intervalMinutes
        self.applicationActivity = applicationActivity
    }
}

public struct JournalEditorDraft: Codable, Equatable, Sendable {
    public var entryID: UUID?
    public var start: Date
    public var end: Date
    public var text: String

    public init(entryID: UUID?, start: Date, end: Date, text: String) {
        self.entryID = entryID
        self.start = start
        self.end = end
        self.text = text
    }
}

public struct AppUpdateContinuation: Codable, Equatable, Sendable {
    public var preparedAt: Date
    public var sourceVersion: String
    public var targetVersion: String
    public var promptEntryID: UUID?
    public var promptQueue: [UUID]?
    public var editorDraft: JournalEditorDraft?

    public init(preparedAt: Date, sourceVersion: String, targetVersion: String, promptEntryID: UUID? = nil, promptQueue: [UUID] = [], editorDraft: JournalEditorDraft? = nil) {
        self.preparedAt = preparedAt
        self.sourceVersion = sourceVersion
        self.targetVersion = targetVersion
        self.promptEntryID = promptEntryID
        self.promptQueue = promptQueue
        self.editorDraft = editorDraft
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
    case invalidApplicationUsage

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
        case .invalidApplicationUsage: return "The saved application usage has invalid times or durations."
        }
    }
}

public struct JournalState: Codable, Equatable, Sendable {
    public var version = 1
    public var entries: [JournalEntry] = []
    public var preferences = Preferences()
    public var session: RecordingSession?
    public var pauseDate: Date?
    public var updateContinuation: AppUpdateContinuation?
    public var editorDraft: JournalEditorDraft?
    public var isRecording: Bool { session != nil }
    public init() {}

    @discardableResult
    public mutating func start(at date: Date) -> Bool {
        guard session == nil, Self.isFinite(date), (1...240).contains(preferences.intervalMinutes),
              !entries.contains(where: { $0.end > date }) else { return false }
        session = RecordingSession(startedAt: date, segmentStartedAt: date, lastHeartbeatAt: date, intervalMinutes: preferences.intervalMinutes,
                                   applicationActivity: preferences.captureApplicationUsage == false ? nil : [])
        pauseDate = nil
        return true
    }

    @discardableResult
    public mutating func pause(at date: Date) -> [UUID] {
        guard pauseDate == nil, let current = session, Self.isFinite(date) else { return [] }
        let ids = advance(to: max(date, current.lastHeartbeatAt))
        pauseDate = session?.lastHeartbeatAt
        return ids
    }

    @discardableResult
    public mutating func resume(at date: Date, recordGap: Bool) -> [UUID] {
        guard let boundary = pauseDate, session != nil, Self.isFinite(date), date >= boundary else { return [] }
        if recordGap {
            pauseDate = nil
            return advance(to: date)
        }
        let ids = stop(at: boundary)
        _ = start(at: date)
        return ids
    }

    public mutating func appendApplicationActivity(_ spans: [ApplicationActivity]) {
        guard pauseDate == nil, var current = session else { return }
        var activity = current.applicationActivity ?? []
        for span in spans.filter(\.isValid).sorted(by: { $0.start < $1.start }) {
            let start = max(max(span.start, current.segmentStartedAt), activity.last?.end ?? current.segmentStartedAt)
            guard start < span.end else { continue }
            let clipped = ApplicationActivity(bundleIdentifier: span.bundleIdentifier, name: span.name, start: start, end: span.end)
            if let last = activity.last, last.end == start, last.identity == clipped.identity {
                activity[activity.count - 1].end = clipped.end
            } else {
                activity.append(clipped)
            }
            current.lastHeartbeatAt = max(current.lastHeartbeatAt, span.end)
        }
        if !activity.isEmpty { current.applicationActivity = activity }
        session = current
    }

    @discardableResult
    public mutating func advance(to date: Date) -> [UUID] {
        guard pauseDate == nil, var current = session, Self.isFinite(date), (1...240).contains(current.intervalMinutes) else { return [] }
        let interval = TimeInterval(current.intervalMinutes * 60)
        var ids: [UUID] = []
        while current.segmentStartedAt.addingTimeInterval(interval) <= date {
            let end = current.segmentStartedAt.addingTimeInterval(interval)
            let usage = current.applicationActivity.map { ApplicationUsageSummary(start: current.segmentStartedAt, end: end, activity: $0) }
            let entry = JournalEntry(start: current.segmentStartedAt, end: end, createdAt: date, applicationUsage: usage)
            entries.append(entry)
            ids.append(entry.id)
            current.segmentStartedAt = end
            current.applicationActivity = current.applicationActivity?.compactMap { span in
                guard span.end > end else { return nil }
                return ApplicationActivity(bundleIdentifier: span.bundleIdentifier, name: span.name, start: max(span.start, end), end: span.end)
            }
        }
        current.lastHeartbeatAt = max(current.lastHeartbeatAt, date)
        session = current
        return ids
    }

    @discardableResult
    public mutating func stop(at date: Date) -> [UUID] {
        guard Self.isFinite(date), session != nil else { return [] }
        let boundary = pauseDate ?? date
        pauseDate = nil
        var ids = advance(to: boundary)
        if let current = session, boundary > current.segmentStartedAt {
            let usage = current.applicationActivity.map { ApplicationUsageSummary(start: current.segmentStartedAt, end: boundary, activity: $0) }
            let entry = JournalEntry(start: current.segmentStartedAt, end: boundary, createdAt: date, applicationUsage: usage)
            entries.append(entry)
            ids.append(entry.id)
        }
        session = nil
        updateContinuation = nil
        return ids
    }

    @discardableResult
    public mutating func recoverInterruptedSession() -> [UUID] {
        updateContinuation = nil
        guard pauseDate == nil, let heartbeat = session?.lastHeartbeatAt else { return [] }
        return stop(at: heartbeat)
    }

    public mutating func consumeUpdateContinuation(at date: Date, appVersion: String) -> AppUpdateContinuation? {
        let continuation = updateContinuation
        updateContinuation = nil
        guard let continuation, Self.isFinite(date), Self.isFinite(continuation.preparedAt),
              !continuation.sourceVersion.isEmpty, !continuation.targetVersion.isEmpty,
              appVersion == continuation.targetVersion || appVersion == continuation.sourceVersion,
              (0...300).contains(date.timeIntervalSince(continuation.preparedAt)),
              session.map({ date >= $0.lastHeartbeatAt }) ?? true else { return nil }
        _ = advance(to: date)
        return continuation
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
            try entry.applicationUsage?.validate()
        }
        if let current = session {
            guard (1...240).contains(current.intervalMinutes) else { throw JournalError.invalidInterval }
            guard Self.isFinite(current.startedAt), Self.isFinite(current.segmentStartedAt), Self.isFinite(current.lastHeartbeatAt),
                  current.startedAt <= current.segmentStartedAt, current.segmentStartedAt <= current.lastHeartbeatAt else { throw JournalError.invalidDates }
            if entries.contains(where: { $0.end > current.segmentStartedAt }) { throw JournalError.activeSessionConflict }
            var previousEnd = current.segmentStartedAt
            for activity in current.applicationActivity ?? [] {
                guard activity.isValid, activity.start >= previousEnd, activity.end <= current.lastHeartbeatAt
                else { throw JournalError.invalidApplicationUsage }
                previousEnd = activity.end
            }
        }
        if let draft = editorDraft {
            guard Self.isFinite(draft.start), Self.isFinite(draft.end) else { throw JournalError.invalidDates }
        }
        if let pauseDate {
            guard let session, Self.isFinite(pauseDate), pauseDate >= session.segmentStartedAt,
                  pauseDate == session.lastHeartbeatAt else { throw JournalError.invalidDates }
        }
    }

    private func checkRange(start: Date, end: Date, excluding id: UUID? = nil) throws {
        guard Self.isFinite(start), Self.isFinite(end), start < end else { throw JournalError.invalidDates }
        if entries.contains(where: { $0.id != id && start < $0.end && end > $0.start }) { throw JournalError.overlappingEntries }
        if let current = session, end > current.segmentStartedAt { throw JournalError.activeSessionConflict }
    }

    private static func isFinite(_ date: Date) -> Bool { date.timeIntervalSinceReferenceDate.isFinite }
}
