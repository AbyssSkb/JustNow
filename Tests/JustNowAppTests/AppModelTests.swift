import Foundation
import XCTest
import JustNowCore
@testable import JustNow

final class AppModelTests: XCTestCase {
    @MainActor
    private func makeModel() -> AppModel {
        let model = AppModel(isDemo: true, showOnboarding: true)
        for entry in model.entries { model.deleteEntry(entry.id) }
        return model
    }

    private func at(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2024, month: 2, day: day, hour: hour, minute: minute))!
    }

    func testPreparedUpdateFlushesDraftAndQuitPreservesRecording() async throws {
        try await MainActor.run {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("justnow-update-\(UUID())")
            defer { try? FileManager.default.removeItem(at: directory) }
            let storage = JournalStorage(directory: directory)
            let date = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
            var state = JournalState()
            let entry = JournalEntry(start: date.addingTimeInterval(-1_800), end: date.addingTimeInterval(-900))
            state.entries = [entry]
            try storage.save(state)
            let model = AppModel(dataDirectory: directory, appVersion: "0.1.8", trackApplicationUsage: false)
            model.startRecording()
            let anchor = try XCTUnwrap(model.journal.session?.startedAt)
            model.openPendingEntry(entry.id)
            model.setDraft(id: entry.id, text: "Typing\na reminder")
            let editor = JournalEditorDraft(entryID: nil, start: date.addingTimeInterval(-3_600), end: date.addingTimeInterval(-2_700), text: "Unsaved editor")
            model.presentedEditor = EntryEditorRequest(entry: nil)
            model.editorDraft = editor
            XCTAssertTrue(model.prepareForUpdate(sourceVersion: "0.1.8", targetVersion: "0.1.9"))
            model.editorDraft = nil // The view can disappear before the final termination checkpoint.
            XCTAssertTrue(model.isRecording)
            XCTAssertTrue(model.prepareForQuit())
            let checkpoint = try storage.load()
            XCTAssertEqual(try XCTUnwrap(checkpoint.session?.startedAt).timeIntervalSince1970, anchor.timeIntervalSince1970, accuracy: 0.000001)
            XCTAssertEqual(try XCTUnwrap(checkpoint.session?.segmentStartedAt).timeIntervalSince1970, anchor.timeIntervalSince1970, accuracy: 0.000001)
            XCTAssertEqual(checkpoint.entries.count, 1)
            XCTAssertEqual(checkpoint.entries.first?.text, "Typing\na reminder")
            XCTAssertEqual(checkpoint.updateContinuation?.promptEntryID, entry.id)
            XCTAssertEqual(checkpoint.updateContinuation?.editorDraft, editor)

            let resumed = AppModel(dataDirectory: directory, appVersion: "0.1.9", trackApplicationUsage: false)
            XCTAssertTrue(resumed.isRecording)
            XCTAssertEqual(try XCTUnwrap(resumed.journal.session?.startedAt).timeIntervalSince1970, anchor.timeIntervalSince1970, accuracy: 0.000001)
            XCTAssertEqual(resumed.promptEntryID, entry.id)
            XCTAssertEqual(resumed.presentedEditor?.draft, editor)
            XCTAssertEqual(resumed.entries.count, 1)
            XCTAssertNil(try storage.load().updateContinuation)
            XCTAssertTrue(resumed.prepareForQuit())
            let normalLaunch = AppModel(dataDirectory: directory, appVersion: "0.1.9", trackApplicationUsage: false)
            XCTAssertFalse(normalLaunch.isRecording)
            XCTAssertNil(normalLaunch.promptEntryID)
        }
    }

    func testRelaunchCrossesBoundaryWithoutSplittingOrDuplicatingAndRestoresQueue() async throws {
        try await MainActor.run {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("justnow-update-\(UUID())")
            defer { try? FileManager.default.removeItem(at: directory) }
            let date = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
            let anchor = date.addingTimeInterval(-1_805)
            var state = JournalState()
            let first = JournalEntry(start: date.addingTimeInterval(-3_600), end: date.addingTimeInterval(-3_500))
            let second = JournalEntry(start: date.addingTimeInterval(-3_400), end: date.addingTimeInterval(-3_300))
            state.entries = [first, second]
            state.start(at: anchor)
            state.advance(to: date.addingTimeInterval(-10))
            state.updateContinuation = AppUpdateContinuation(preparedAt: date.addingTimeInterval(-10), sourceVersion: "0.1.8", targetVersion: "0.1.9", promptEntryID: first.id, promptQueue: [second.id])
            let storage = JournalStorage(directory: directory)
            try storage.save(state)
            let model = AppModel(dataDirectory: directory, appVersion: "0.1.9", trackApplicationUsage: false)
            XCTAssertTrue(model.isRecording)
            XCTAssertEqual(model.journal.session?.startedAt, anchor)
            XCTAssertEqual(model.currentSegmentStart, anchor.addingTimeInterval(1_800))
            XCTAssertEqual(model.entries.count, 3)
            let due = try XCTUnwrap(model.entries.last)
            XCTAssertEqual(due.start, anchor)
            XCTAssertEqual(due.end, anchor.addingTimeInterval(1_800))
            XCTAssertEqual(model.promptEntryID, first.id)
            XCTAssertTrue(model.savePrompt(id: first.id, text: "First completed"))
            XCTAssertEqual(model.promptEntryID, second.id)
            XCTAssertTrue(model.savePrompt(id: second.id, text: "Second completed"))
            XCTAssertEqual(model.promptEntryID, due.id)
            XCTAssertNil(try storage.load().updateContinuation)
        }
    }

    func testUpdateConsumesContinuationAndKeepsNewAndExistingDraftsRecoverable() async throws {
        try await MainActor.run {
            for editingExisting in [false, true] {
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent("justnow-update-\(UUID())")
                defer { try? FileManager.default.removeItem(at: directory) }
                let date = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
                let entry = JournalEntry(start: date.addingTimeInterval(-1_800), end: date.addingTimeInterval(-900), text: "Saved original", status: .recorded)
                let draft = JournalEditorDraft(entryID: editingExisting ? entry.id : nil, start: entry.start, end: entry.end, text: "Unsubmitted\neditor text")
                var state = JournalState()
                state.entries = [entry]
                state.updateContinuation = AppUpdateContinuation(preparedAt: date, sourceVersion: "0.1.8", targetVersion: "0.1.9", editorDraft: draft)
                let storage = JournalStorage(directory: directory)
                try storage.save(state)
                let model = AppModel(dataDirectory: directory, appVersion: "0.1.9", trackApplicationUsage: false)
                XCTAssertFalse(model.isRecording)
                XCTAssertEqual(model.editorDraft, draft)
                XCTAssertEqual(model.presentedEditor?.draft, draft)
                XCTAssertEqual(model.presentedEditor?.entry?.id, draft.entryID)
                XCTAssertEqual(model.entries.first?.text, "Saved original")
                XCTAssertNil(try storage.load().updateContinuation)
                let repeated = AppModel(dataDirectory: directory, appVersion: "0.1.9", trackApplicationUsage: false)
                XCTAssertEqual(repeated.presentedEditor?.draft, draft)
                XCTAssertNil(repeated.journal.updateContinuation)
                XCTAssertFalse(repeated.isRecording)
            }
        }
    }

    func testStaleWrongVersionAndFutureUpdateLaunchesEndAtTheSavedHeartbeat() async throws {
        try await MainActor.run {
            let date = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
            for (preparedAt, appVersion) in [(date.addingTimeInterval(-600), "0.1.9"), (date, "other"), (date.addingTimeInterval(60), "0.1.9")] {
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent("justnow-update-\(UUID())")
                defer { try? FileManager.default.removeItem(at: directory) }
                let heartbeat = date.addingTimeInterval(-2_400)
                var state = JournalState()
                state.start(at: date.addingTimeInterval(-3_600))
                state.advance(to: heartbeat)
                state.updateContinuation = AppUpdateContinuation(preparedAt: preparedAt, sourceVersion: "0.1.8", targetVersion: "0.1.9")
                let storage = JournalStorage(directory: directory)
                try storage.save(state)
                let model = AppModel(dataDirectory: directory, appVersion: appVersion, trackApplicationUsage: false)
                XCTAssertFalse(model.isRecording)
                XCTAssertEqual(model.entries.count, 1)
                XCTAssertEqual(model.entries.first?.end, heartbeat)
                XCTAssertNil(model.journal.updateContinuation)
                XCTAssertNil(try storage.load().updateContinuation)
                XCTAssertFalse(model.hasStorageError)
            }
        }
    }

    func testFailedUpdateCheckpointDoesNotArmQuitAndCancellationLeavesRecordingActive() async throws {
        try await MainActor.run {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("justnow-update-\(UUID())")
            defer { try? FileManager.default.removeItem(at: directory) }
            let model = AppModel(dataDirectory: directory, appVersion: "0.1.8", trackApplicationUsage: false)
            model.startRecording()
            let storage = JournalStorage(directory: directory)
            let intact = try Data(contentsOf: storage.fileURL)
            let corrupt = Data("unwritable checkpoint".utf8)
            try corrupt.write(to: storage.fileURL)
            XCTAssertFalse(model.prepareForUpdate(sourceVersion: "0.1.8", targetVersion: "0.1.9"))
            XCTAssertNil(model.journal.updateContinuation)
            XCTAssertTrue(model.isRecording)
            XCTAssertEqual(try Data(contentsOf: storage.fileURL), corrupt)
            try intact.write(to: storage.fileURL)
            XCTAssertTrue(model.prepareForQuit())
            XCTAssertFalse(model.isRecording)

            model.startRecording()
            let anchor = model.journal.session?.startedAt
            XCTAssertTrue(model.prepareForUpdate(sourceVersion: "0.1.8", targetVersion: "0.1.9"))
            XCTAssertTrue(model.cancelPreparedUpdate())
            XCTAssertTrue(model.isRecording)
            XCTAssertEqual(model.journal.session?.startedAt, anchor)
            XCTAssertNil(try storage.load().updateContinuation)
            XCTAssertTrue(model.prepareForQuit())
            XCTAssertFalse(model.isRecording)
        }
    }

    func testTodayRollsOverAndPromptSaveUpdatesCountsWithoutNavigation() async throws {
        try await MainActor.run {
            let model = makeModel()
            defer { try? FileManager.default.removeItem(at: model.dataDirectory) }
            model.now = at(6, 23, 55)
            model.selectedDay = model.now
            XCTAssertTrue(model.saveEditedEntry(id: nil, start: at(6, 22, 0), end: at(6, 22, 30), text: "Earlier"))
            XCTAssertTrue(model.saveEditedEntry(id: nil, start: at(6, 23, 50), end: at(7, 0, 20), text: "Draft"))
            let id = try XCTUnwrap(model.entries.last?.id)
            model.setDraft(id: id, text: "Unfinished note")
            model.dismissPrompt()
            XCTAssertEqual(model.completedCount, 1)
            XCTAssertEqual(model.pendingCount, 1)
            XCTAssertEqual(model.recordedDuration, 1_800)

            model.now = at(7, 0, 25)
            XCTAssertEqual(model.displayDay, model.now)
            XCTAssertEqual(model.selectedDay, at(6, 23, 55))
            XCTAssertEqual(model.selectedDayEntries.map(\.id), [id])
            XCTAssertEqual(model.completedCount, 0)
            XCTAssertEqual(model.pendingCount, 1)
            XCTAssertEqual(model.todayPendingCount, 1)
            XCTAssertEqual(model.recordedDuration, 0)

            model.openPendingEntry(id)
            XCTAssertEqual(model.promptEntryID, id)
            XCTAssertTrue(model.savePrompt(id: id, text: "Finished across midnight"))
            XCTAssertEqual(model.selectedSection, .today)
            XCTAssertEqual(model.selectedDayEntries.first?.text, "Finished across midnight")
            XCTAssertEqual(model.completedCount, 1)
            XCTAssertEqual(model.pendingCount, 0)
            XCTAssertEqual(model.todayPendingCount, 0)
            XCTAssertEqual(model.recordedDuration, 1_200)
            XCTAssertNil(model.promptEntryID)
        }
    }

    func testHistoryKeepsItsSelectedDateAndSearchWhenTodayChanges() async throws {
        try await MainActor.run {
            let model = makeModel()
            defer { try? FileManager.default.removeItem(at: model.dataDirectory) }
            XCTAssertTrue(model.saveEditedEntry(id: nil, start: at(6, 9, 0), end: at(6, 9, 30), text: "Read a paper"))
            XCTAssertTrue(model.saveEditedEntry(id: nil, start: at(6, 10, 0), end: at(6, 10, 15), text: "Write notes"))
            XCTAssertTrue(model.saveEditedEntry(id: nil, start: at(7, 0, 0), end: at(7, 0, 20), text: "Read more"))
            let firstDayIDs = Array(model.entries.prefix(2)).map(\.id)
            model.selectedSection = .history
            model.selectedDay = at(6, 12, 0)
            model.searchText = "read"
            model.now = at(7, 0, 25)
            XCTAssertEqual(model.displayDay, model.selectedDay)
            XCTAssertEqual(model.selectedDayEntries.map(\.id), [firstDayIDs[0]])
            XCTAssertEqual(model.completedCount, 1)
            XCTAssertEqual(model.recordedDuration, 1_800)

            model.now = at(8, 0, 25)
            XCTAssertEqual(model.selectedDay, at(6, 12, 0))
            XCTAssertEqual(model.searchText, "read")
            XCTAssertEqual(model.selectedDayEntries.map(\.id), [firstDayIDs[0]])
            model.searchText = ""
            XCTAssertEqual(model.selectedDayEntries.map(\.id), firstDayIDs)
            XCTAssertEqual(model.completedCount, 2)
            XCTAssertEqual(model.recordedDuration, 2_700)
            XCTAssertTrue(model.saveEditedEntry(id: nil, start: at(8, 0, 0), end: at(8, 0, 20), text: "Today's draft"))
            let id = try XCTUnwrap(model.entries.last?.id)
            model.setDraft(id: id, text: "Unfinished")
            model.dismissPrompt()
            model.searchText = "no match"
            XCTAssertTrue(model.selectedDayEntries.isEmpty)
            XCTAssertEqual(model.pendingCount, 0)
            XCTAssertEqual(model.todayPendingCount, 1)
        }
    }

    func testSameDaySaveEditDraftAndDeleteAppearImmediately() async throws {
        try await MainActor.run {
            let model = makeModel()
            defer { try? FileManager.default.removeItem(at: model.dataDirectory) }
            model.now = at(7, 12, 0)
            model.selectedDay = model.now
            XCTAssertTrue(model.saveEditedEntry(id: nil, start: at(7, 9, 0), end: at(7, 9, 30), text: "First"))
            XCTAssertTrue(model.saveEditedEntry(id: nil, start: at(7, 10, 0), end: at(7, 10, 30), text: "Second"))
            let id = try XCTUnwrap(model.entries.last?.id)
            XCTAssertEqual(model.selectedDayEntries.map(\.text), ["Second", "First"])

            XCTAssertFalse(model.saveEditedEntry(id: id, start: at(7, 10, 0), end: at(7, 9, 45), text: "Edited"))
            XCTAssertNotNil(model.errorMessage)
            XCTAssertTrue(model.saveEditedEntry(id: id, start: at(7, 10, 0), end: at(7, 10, 45), text: "Edited"))
            XCTAssertNil(model.errorMessage)
            XCTAssertEqual(model.selectedDayEntries.first?.text, "Edited")
            XCTAssertEqual(model.recordedDuration, 4_500)
            model.setDraft(id: id, text: "Still editing")
            model.dismissPrompt()
            XCTAssertEqual(model.selectedDayEntries.first?.text, "Still editing")
            XCTAssertEqual(model.pendingCount, 1)
            XCTAssertEqual(model.completedCount, 1)
            XCTAssertEqual(model.recordedDuration, 1_800)
            XCTAssertFalse(model.savePrompt(id: id, text: " \n"))
            XCTAssertNotNil(model.errorMessage)
            XCTAssertTrue(model.savePrompt(id: id, text: "Done"))
            XCTAssertNil(model.errorMessage)
            XCTAssertEqual(model.selectedDayEntries.first?.text, "Done")
            XCTAssertEqual(model.pendingCount, 0)
            XCTAssertEqual(model.completedCount, 2)
            XCTAssertEqual(model.recordedDuration, 4_500)

            model.deleteEntry(id)
            XCTAssertEqual(model.selectedDayEntries.map(\.text), ["First"])
            XCTAssertEqual(model.completedCount, 1)
            XCTAssertEqual(model.recordedDuration, 1_800)
            XCTAssertEqual(model.selectedSection, .today)
        }
    }
}
