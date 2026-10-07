import Foundation
import XCTest
@testable import JustNowCore

final class JournalTests: XCTestCase {
    private let origin = Date(timeIntervalSince1970: 1_800_000_000)
    private func at(_ minutes: Double) -> Date { origin.addingTimeInterval(minutes * 60) }

    func testDelayedReminderKeepsTheOriginalAnchorWithoutDuplicates() throws {
        var state = JournalState()
        XCTAssertTrue(state.start(at: at(0)))
        XCTAssertFalse(state.start(at: at(1)))
        XCTAssertEqual(state.advance(to: at(97)).count, 3)
        XCTAssertEqual(state.entries.map(\.start), [at(0), at(30), at(60)])
        XCTAssertEqual(state.entries.map(\.end), [at(30), at(60), at(90)])
        XCTAssertTrue(state.entries.allSatisfy(\.isPending))
        XCTAssertEqual(state.session?.segmentStartedAt, at(90))
        XCTAssertTrue(state.advance(to: at(97)).isEmpty)
        XCTAssertTrue(state.advance(to: at(95)).isEmpty)
        XCTAssertEqual(state.session?.lastHeartbeatAt, at(97))
        try state.validate()
    }

    func testStopPreservesThePartialIntervalAndIsIdempotent() throws {
        var state = JournalState()
        state.start(at: at(0))
        XCTAssertEqual(state.stop(at: at(65)).count, 3)
        XCTAssertEqual(state.entries.map(\.duration), [1_800, 1_800, 300])
        XCTAssertFalse(state.isRecording)
        XCTAssertTrue(state.stop(at: at(70)).isEmpty)
        try state.validate()

        var exact = JournalState()
        exact.start(at: at(0))
        XCTAssertEqual(exact.stop(at: at(30)).count, 1)
        var immediate = JournalState()
        immediate.start(at: at(0))
        XCTAssertTrue(immediate.stop(at: at(0)).isEmpty)
    }

    func testCrashRecoveryEndsAtTheLastSavedHeartbeat() throws {
        var state = JournalState()
        state.start(at: at(0))
        state.advance(to: at(42))
        XCTAssertEqual(state.recoverInterruptedSession().count, 1)
        XCTAssertEqual(state.entries.last?.start, at(30))
        XCTAssertEqual(state.entries.last?.end, at(42))
        XCTAssertFalse(state.isRecording)
        XCTAssertTrue(state.recoverInterruptedSession().isEmpty)
        try state.validate()
    }

    func testUpdateContinuationKeepsTheSessionAnchorAndIsConsumedOnce() throws {
        var state = JournalState()
        state.start(at: at(0))
        state.advance(to: at(29))
        let draft = JournalEditorDraft(entryID: nil, start: at(-30), end: at(-10), text: "Unsubmitted\nnew note")
        state.updateContinuation = AppUpdateContinuation(preparedAt: at(29), sourceVersion: "0.1.8", targetVersion: "0.1.9", editorDraft: draft)
        let continuation = try XCTUnwrap(state.consumeUpdateContinuation(at: at(31), appVersion: "0.1.9"))
        XCTAssertEqual(continuation.editorDraft, draft)
        XCTAssertEqual(state.session?.startedAt, at(0))
        XCTAssertEqual(state.session?.segmentStartedAt, at(30))
        XCTAssertEqual(state.session?.intervalMinutes, 30)
        XCTAssertEqual(state.entries.map(\.start), [at(0)])
        XCTAssertEqual(state.entries.map(\.end), [at(30)])
        XCTAssertTrue(state.advance(to: at(31)).isEmpty)
        XCTAssertNil(state.updateContinuation)
        XCTAssertNil(state.consumeUpdateContinuation(at: at(32), appVersion: "0.1.9"))
        XCTAssertEqual(state.recoverInterruptedSession().count, 1)
        XCTAssertEqual(state.entries.last?.end, at(31))
        XCTAssertFalse(state.isRecording)
        try state.validate()
    }

    func testInvalidUpdateContinuationsRecoverOnlyToTheSavedHeartbeat() throws {
        let cases: [(Date, Date, String)] = [
            (at(20), at(26), "0.1.9"),
            (at(20), at(19), "0.1.9"),
            (at(20), at(21), "unrelated"),
            (Date(timeIntervalSinceReferenceDate: .infinity), at(21), "0.1.9")
        ]
        for (preparedAt, launchAt, version) in cases {
            var state = JournalState()
            state.start(at: at(0))
            state.advance(to: at(20))
            state.updateContinuation = AppUpdateContinuation(preparedAt: preparedAt, sourceVersion: "0.1.8", targetVersion: "0.1.9")
            XCTAssertNil(state.consumeUpdateContinuation(at: launchAt, appVersion: version))
            XCTAssertNil(state.updateContinuation)
            _ = state.recoverInterruptedSession()
            XCTAssertFalse(state.isRecording)
            XCTAssertEqual(state.entries.map(\.end), [at(20)])
            try state.validate()
        }
    }

    func testRollbackAndIdleUpdateDoNotStartAnIdleSession() throws {
        var idle = JournalState()
        idle.updateContinuation = AppUpdateContinuation(preparedAt: at(20), sourceVersion: "0.1.8", targetVersion: "0.1.9")
        XCTAssertNotNil(idle.consumeUpdateContinuation(at: at(21), appVersion: "0.1.8"))
        XCTAssertFalse(idle.isRecording)
        XCTAssertTrue(idle.entries.isEmpty)

        var recording = JournalState()
        recording.start(at: at(0))
        recording.advance(to: at(20))
        recording.updateContinuation = AppUpdateContinuation(preparedAt: at(20), sourceVersion: "0.1.8", targetVersion: "0.1.9")
        XCTAssertNotNil(recording.consumeUpdateContinuation(at: at(21), appVersion: "0.1.8"))
        XCTAssertEqual(recording.session?.startedAt, at(0))
        recording.recoverInterruptedSession()
        XCTAssertNil(recording.updateContinuation)
    }

    func testIntervalChangesApplyToTheNextSession() throws {
        var state = JournalState()
        state.start(at: at(0))
        state.preferences.intervalMinutes = 15
        XCTAssertTrue(state.advance(to: at(15)).isEmpty)
        XCTAssertEqual(state.advance(to: at(30)).count, 1)
        state.stop(at: at(30))
        state.start(at: at(30))
        XCTAssertEqual(state.advance(to: at(45)).count, 1)
        XCTAssertEqual(state.entries.last?.duration, 900)
        try state.validate()
    }

    func testDraftSurvivesAndRecordingRequiresANonemptyNote() throws {
        var state = JournalState()
        state.start(at: at(0))
        let id = try XCTUnwrap(state.stop(at: at(30)).first)
        state.setDraft(id: id, text: "A thought in progress")
        XCTAssertTrue(state.entries[0].isPending)
        XCTAssertEqual(state.entries[0].text, "A thought in progress")
        let before = state
        XCTAssertThrowsError(try state.updateEntry(id: id, text: " \n\t")) { XCTAssertEqual($0 as? JournalError, .emptyNote) }
        XCTAssertEqual(state, before)
        try state.updateEntry(id: id, text: "  Read a paper\n")
        XCTAssertEqual(state.entries[0].text, "Read a paper")
        XCTAssertFalse(state.entries[0].isPending)
        try state.updateEntry(id: id, text: "", markRecorded: false)
        XCTAssertTrue(state.entries[0].isPending)
        try state.validate()
    }

    func testManualRangesCanTouchButCannotOverlap() throws {
        var state = JournalState()
        let first = try state.insertEntry(start: at(0), end: at(30), text: "Read")
        let second = try state.insertEntry(start: at(30), end: at(60), text: "Write")
        XCTAssertThrowsError(try state.insertEntry(start: at(20), end: at(40), text: "Overlap")) { XCTAssertEqual($0 as? JournalError, .overlappingEntries) }
        XCTAssertThrowsError(try state.updateEntry(id: second, text: "Write", start: at(29))) { XCTAssertEqual($0 as? JournalError, .overlappingEntries) }
        try state.updateEntry(id: first, text: "Read carefully", end: at(25))
        XCTAssertTrue(state.start(at: at(60)))
        XCTAssertThrowsError(try state.insertEntry(start: at(60), end: at(65), text: "Active")) { XCTAssertEqual($0 as? JournalError, .activeSessionConflict) }
        state.deleteEntry(id: first)
        XCTAssertEqual(state.entries.map(\.id), [second])
        try state.validate()
    }

    func testValidationRejectsCorruptState() throws {
        var state = JournalState()
        state.preferences.intervalMinutes = 0
        XCTAssertThrowsError(try state.validate()) { XCTAssertEqual($0 as? JournalError, .invalidInterval) }
        XCTAssertFalse(state.start(at: at(0)))
        state.preferences.intervalMinutes = 241
        XCTAssertThrowsError(try state.validate())
        state.preferences.intervalMinutes = 30
        state.version = 2
        XCTAssertThrowsError(try state.validate()) { XCTAssertEqual($0 as? JournalError, .unsupportedVersion(2)) }
        state.version = 1
        let entry = JournalEntry(start: at(0), end: at(30), text: "Read", status: .recorded, createdAt: at(30))
        state.entries = [entry, entry]
        XCTAssertThrowsError(try state.validate()) { XCTAssertEqual($0 as? JournalError, .duplicateID) }
        state.entries = [JournalEntry(start: at(30), end: at(0))]
        XCTAssertThrowsError(try state.validate()) { XCTAssertEqual($0 as? JournalError, .invalidDates) }
        state.entries = [JournalEntry(start: at(0), end: Date(timeIntervalSinceReferenceDate: .infinity))]
        XCTAssertThrowsError(try state.validate()) { XCTAssertEqual($0 as? JournalError, .invalidDates) }
        state.entries = [JournalEntry(start: at(0), end: at(30), text: " ", status: .recorded)]
        XCTAssertThrowsError(try state.validate()) { XCTAssertEqual($0 as? JournalError, .emptyNote) }
        state.entries = []
        state.session = RecordingSession(startedAt: at(0), segmentStartedAt: at(30), lastHeartbeatAt: at(20), intervalMinutes: 30)
        XCTAssertThrowsError(try state.validate()) { XCTAssertEqual($0 as? JournalError, .invalidDates) }
    }

    func testStorageRoundTripBackupAndCorruptPrimaryRecovery() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("justnow-tests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = JournalStorage(directory: directory)
        XCTAssertEqual(try storage.load(), JournalState())
        var first = JournalState()
        first.start(at: at(0))
        let id = try XCTUnwrap(first.stop(at: at(30)).first)
        first.setDraft(id: id, text: "My unfinished note")
        try storage.save(first)
        XCTAssertEqual(try storage.load(), first)
        var second = first
        try second.updateEntry(id: id, text: "My finished note")
        try storage.save(second)
        XCTAssertEqual(try storage.load(), second)
        let corrupted = Data("invalid journal".utf8)
        try corrupted.write(to: storage.fileURL)
        XCTAssertThrowsError(try storage.load())
        XCTAssertThrowsError(try storage.save(JournalState()))
        XCTAssertEqual(try Data(contentsOf: storage.fileURL), corrupted)
        XCTAssertEqual(try storage.restoreBackup(), first)
        XCTAssertEqual(try storage.load(), first)
        let preserved = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("journal.corrupt-") }
        XCTAssertEqual(preserved.count, 1)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(preserved.first)), corrupted)
        try corrupted.write(to: directory.appendingPathComponent("journal.previous.json"))
        XCTAssertThrowsError(try storage.restoreBackup())
        XCTAssertEqual(try storage.load(), first)
    }

    func testCSVProtectsHostileNotesAndJSONUsesISODates() throws {
        let note = "  =SUM(A1:A2)\n\"quoted\", comma"
        let entry = JournalEntry(start: at(0), end: at(30), text: note, status: .recorded)
        let csv = JournalExport.csv(entries: [entry])
        XCTAssertTrue(csv.hasPrefix("Start,End,Duration (minutes),Status,Note\r\n"))
        XCTAssertTrue(csv.contains("\"'  =SUM(A1:A2)\n\"\"quoted\"\", comma\""))
        for value in ["+1", "\t-1", "\n@command"] {
            let candidate = JournalEntry(start: at(0), end: at(30), text: value)
            XCTAssertTrue(JournalExport.csv(entries: [candidate]).contains("\"'\(value)\""))
        }
        let data = try JournalExport.json(entries: [entry])
        let rows = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let start = try XCTUnwrap(rows.first?["start"] as? String)
        XCTAssertTrue(start.contains("T"))
        XCTAssertTrue(start.hasSuffix("Z"))
        XCTAssertEqual(rows.first?["text"] as? String, note)
    }
}
