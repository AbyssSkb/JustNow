import Foundation
import XCTest
import JustNowCore
@testable import JustNow

final class DraftRecoveryTests: XCTestCase {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("justnow-draft-\(UUID())")
    }

    func testFailedSaveRetainsApplicationObservationsUntilSuccessfulStop() async throws {
        try await MainActor.run {
            let directory = directory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let tracker = ApplicationUsageTracker(frontmostApplication: {
                ApplicationUsageTracker.Application(bundleIdentifier: "test.editor", name: "Editor")
            }, observeWorkspace: false)
            let model = AppModel(dataDirectory: directory, applicationTracker: tracker)
            model.startRecording()
            XCTAssertTrue(tracker.isTracking)
            let first = try XCTUnwrap(tracker.snapshot(at: Date()).first)
            let storage = JournalStorage(directory: directory)
            let intact = try Data(contentsOf: storage.fileURL)
            try Data("invalid journal".utf8).write(to: storage.fileURL)
            var preferences = model.preferences
            preferences.playSound = false
            model.updatePreferences(preferences)
            XCTAssertNotNil(model.errorMessage)
            XCTAssertEqual(tracker.snapshot(at: Date()).first?.start, first.start)
            XCTAssertTrue(model.isRecording)

            try intact.write(to: storage.fileURL)
            model.stopRecording()
            let saved = try storage.load()
            XCTAssertEqual(saved.entries.last?.applicationUsage?.applications.first?.name, "Editor")
            XCTAssertGreaterThan(saved.entries.last?.applicationUsage?.observedSeconds ?? 0, 0)
            XCTAssertTrue(tracker.snapshot(at: Date()).isEmpty)
            XCTAssertFalse(tracker.isTracking)
        }
    }

    func testDebouncedDraftSurvivesUnexpectedExitWithoutChangingOriginalEntry() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let date = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
        let original = JournalEntry(start: date.addingTimeInterval(-7_200), end: date.addingTimeInterval(-5_400), text: "Original note", status: .recorded, createdAt: date)
        let storage = JournalStorage(directory: directory)
        var state = JournalState()
        state.entries = [original]
        try storage.save(state)
        let model = await MainActor.run { AppModel(dataDirectory: directory, trackApplicationUsage: false) }
        let draft = JournalEditorDraft(entryID: original.id, start: original.start.addingTimeInterval(60), end: original.end.addingTimeInterval(-60), text: "Unsubmitted\nchanges")
        await MainActor.run {
            model.openEditor(original)
            model.editorDraft = draft
            model.startRecording()
        }
        try await Task.sleep(for: .milliseconds(800))
        XCTAssertEqual(try storage.load().editorDraft, draft)
        XCTAssertEqual(try storage.load().entries.first, original)
        await MainActor.run {
            let relaunched = AppModel(dataDirectory: directory, trackApplicationUsage: false)
            XCTAssertEqual(relaunched.editorDraft, draft)
            XCTAssertEqual(relaunched.presentedEditor?.draft, draft)
            XCTAssertEqual(relaunched.presentedEditor?.entry?.id, original.id)
            XCTAssertEqual(relaunched.entries.first, original)
            XCTAssertFalse(relaunched.isRecording)
        }
    }

    func testOrdinaryQuitPreservesNewDraftAndStillRequiresManualRecordingStart() async {
        await MainActor.run {
            let directory = directory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let date = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
            let draft = JournalEditorDraft(entryID: nil, start: date.addingTimeInterval(-3_600), end: date.addingTimeInterval(-1_800), text: "A new entry\nnot yet submitted")
            let model = AppModel(dataDirectory: directory, trackApplicationUsage: false)
            model.openEditor()
            model.editorDraft = draft
            model.startRecording()
            XCTAssertTrue(model.prepareForQuit())
            let relaunched = AppModel(dataDirectory: directory, trackApplicationUsage: false)
            XCTAssertEqual(relaunched.editorDraft, draft)
            XCTAssertEqual(relaunched.presentedEditor?.draft, draft)
            XCTAssertNil(relaunched.presentedEditor?.entry)
            XCTAssertFalse(relaunched.isRecording)
            XCTAssertFalse(relaunched.entries.contains(where: { $0.text == draft.text }))
        }
    }

    func testCancelSaveAndDeleteClearDraftInTheJournal() async throws {
        try await MainActor.run {
            for action in ["cancel", "save", "delete"] {
                let directory = directory()
                defer { try? FileManager.default.removeItem(at: directory) }
                let date = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
                let original = JournalEntry(start: date.addingTimeInterval(-3_600), end: date.addingTimeInterval(-1_800), text: "Original note", status: .recorded, createdAt: date)
                var state = JournalState()
                state.entries = [original]
                let storage = JournalStorage(directory: directory)
                try storage.save(state)
                let model = AppModel(dataDirectory: directory, trackApplicationUsage: false)
                model.openEditor(original)
                model.editorDraft = JournalEditorDraft(entryID: original.id, start: original.start, end: original.end, text: "Draft changes")
                switch action {
                case "cancel":
                    XCTAssertTrue(model.discardEditorDraft())
                    XCTAssertEqual(try storage.load().entries, [original])
                case "save":
                    XCTAssertTrue(model.saveEditedEntry(id: original.id, start: original.start, end: original.end, text: "Submitted note"))
                    XCTAssertEqual(try storage.load().entries.first?.text, "Submitted note")
                    XCTAssertEqual(try storage.load().entries.first?.status, .recorded)
                default:
                    model.deleteEntry(original.id)
                    XCTAssertTrue(try storage.load().entries.isEmpty)
                }
                XCTAssertNil(model.editorDraft)
                XCTAssertNil(try storage.load().editorDraft)
                XCTAssertNil(AppModel(dataDirectory: directory, trackApplicationUsage: false).presentedEditor)
            }
        }
    }

    func testFailedSaveAndCancelKeepRecoverableDraftAndOriginalEntry() async throws {
        try await MainActor.run {
            let directory = directory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let date = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
            let original = JournalEntry(start: date.addingTimeInterval(-3_600), end: date.addingTimeInterval(-1_800), text: "Original note", status: .recorded, createdAt: date)
            let draft = JournalEditorDraft(entryID: original.id, start: original.end, end: original.start, text: "Still correcting the times")
            var state = JournalState()
            state.entries = [original]
            let storage = JournalStorage(directory: directory)
            try storage.save(state)
            let model = AppModel(dataDirectory: directory, trackApplicationUsage: false)
            model.openEditor(original)
            model.editorDraft = draft
            XCTAssertTrue(model.prepareForQuit())
            XCTAssertFalse(model.saveEditedEntry(id: original.id, start: draft.start, end: draft.end, text: draft.text))
            XCTAssertEqual(try storage.load().editorDraft, draft)
            XCTAssertEqual(try storage.load().entries, [original])
            let intact = try Data(contentsOf: storage.fileURL)
            try Data("invalid journal".utf8).write(to: storage.fileURL)
            XCTAssertFalse(model.discardEditorDraft())
            XCTAssertEqual(model.editorDraft, draft)
            XCTAssertNotNil(model.presentedEditor)
            try intact.write(to: storage.fileURL)
            XCTAssertEqual(AppModel(dataDirectory: directory, trackApplicationUsage: false).presentedEditor?.draft, draft)
        }
    }
}
