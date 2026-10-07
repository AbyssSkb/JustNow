import Foundation
import XCTest
import JustNowCore
@testable import JustNow

final class RecordingLifecycleTests: XCTestCase {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("justnow-lifecycle-\(UUID())")
    }

    private func activeState(at date: Date) -> JournalState {
        var state = JournalState()
        state.preferences.completedOnboarding = true
        state.preferences.captureApplicationUsage = false
        state.start(at: date.addingTimeInterval(-1_200))
        state.advance(to: date.addingTimeInterval(-1))
        state.updateContinuation = AppUpdateContinuation(preparedAt: date.addingTimeInterval(-1), sourceVersion: "0.1.9", targetVersion: "0.1.9")
        return state
    }

    func testLaunchAutoStartsAfterOnboardingAndRespectsOptOutAndIdleUpdate() async throws {
        try await MainActor.run {
            for enabled in [nil, true, false] as [Bool?] {
                let directory = directory()
                defer { try? FileManager.default.removeItem(at: directory) }
                var state = JournalState()
                state.preferences.completedOnboarding = true
                state.preferences.autoStartRecording = enabled
                try JournalStorage(directory: directory).save(state)
                let model = AppModel(dataDirectory: directory, appVersion: "0.1.9", trackApplicationUsage: false, idleSeconds: { 0 })
                model.beginOnLaunch()
                XCTAssertEqual(model.isRecording, enabled != false)
                XCTAssertTrue(model.prepareForQuit())
                let relaunched = AppModel(dataDirectory: directory, appVersion: "0.1.9", trackApplicationUsage: false, idleSeconds: { 0 })
                relaunched.beginOnLaunch()
                XCTAssertEqual(relaunched.isRecording, enabled != false)
            }
            let directory = directory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let model = AppModel(dataDirectory: directory, appVersion: "0.1.9", trackApplicationUsage: false, idleSeconds: { 0 })
            model.beginOnLaunch()
            XCTAssertFalse(model.isRecording)
            model.completeOnboarding()
            XCTAssertTrue(model.isRecording)
            XCTAssertTrue(model.prepareForQuit())
            var state = try JournalStorage(directory: directory).load()
            state.updateContinuation = AppUpdateContinuation(preparedAt: Date(), sourceVersion: "0.1.9", targetVersion: "0.1.9")
            try JournalStorage(directory: directory).save(state)
            let updatedIdle = AppModel(dataDirectory: directory, appVersion: "0.1.9", trackApplicationUsage: false, idleSeconds: { 0 })
            updatedIdle.beginOnLaunch()
            XCTAssertFalse(updatedIdle.isRecording)
        }
    }

    func testIdlePauseUsesDetectionTimeAndOffersResolutionOnlyOnceAfterInput() async throws {
        try await MainActor.run {
            let directory = directory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let date = Date()
            let storage = JournalStorage(directory: directory)
            try storage.save(activeState(at: date))
            var inactivity: TimeInterval = 1_799
            var presentations = 0
            let model = AppModel(dataDirectory: directory, appVersion: "0.1.9", trackApplicationUsage: false, idleSeconds: { inactivity })
            model.onShowMainWindow = { presentations += 1 }
            model.tick(at: Date())
            XCTAssertFalse(model.isPaused)
            inactivity = 1_800
            let detection = Date()
            model.tick(at: detection)
            XCTAssertEqual(model.pauseDate, detection)
            XCTAssertFalse(model.isRecording)
            let frozen = model.journal
            model.tick(at: detection.addingTimeInterval(86_400))
            XCTAssertEqual(model.journal, frozen)
            XCTAssertFalse(model.showingPauseResolution)
            inactivity = 0
            model.tick(at: Date())
            XCTAssertTrue(model.showingPauseResolution)
            XCTAssertEqual(presentations, 1)
            model.showingPauseResolution = false
            model.tick(at: Date())
            XCTAssertFalse(model.showingPauseResolution)
            XCTAssertEqual(presentations, 1)
            XCTAssertTrue(model.resolvePause(recordGap: false))
            XCTAssertTrue(model.isRecording)
            XCTAssertNil(model.pauseDate)
            XCTAssertEqual(model.entries.count, 1)
            XCTAssertEqual(model.entries.first?.end, detection)
            XCTAssertLessThan(model.entries.first?.duration ?? 0, 1_300)
        }
    }

    func testAllEnvironmentGatesMustClearAndWakeDoesNotResumeRecording() async throws {
        try await MainActor.run {
            let directory = directory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let date = Date()
            var state = activeState(at: date)
            state.preferences.pauseWhenInactive = false
            try JournalStorage(directory: directory).save(state)
            let model = AppModel(dataDirectory: directory, appVersion: "0.1.9", trackApplicationUsage: false, idleSeconds: { 0 })
            model.setEnvironmentPaused(true, for: .screenSleep)
            model.handleSleep()
            model.setEnvironmentPaused(true, for: .inactiveSession)
            let boundary = model.pauseDate
            model.handleWake()
            model.tick(at: Date())
            XCTAssertFalse(model.showingPauseResolution)
            XCTAssertFalse(model.resolvePause(recordGap: false))
            model.setEnvironmentPaused(false, for: .screenSleep)
            model.tick(at: Date())
            XCTAssertFalse(model.showingPauseResolution)
            model.setEnvironmentPaused(false, for: .inactiveSession)
            XCTAssertEqual(model.pauseDate, boundary)
            XCTAssertFalse(model.isRecording)
            model.tick(at: Date())
            XCTAssertTrue(model.showingPauseResolution)
            XCTAssertTrue(model.resolvePause(recordGap: false))
            XCTAssertTrue(model.isRecording)
        }
    }

    func testPausedQuitAndUpdateStayFrozenUntilGapIsExplicitlyRecorded() async throws {
        try await MainActor.run {
            let directory = directory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let date = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
            var state = JournalState()
            state.preferences.completedOnboarding = true
            state.start(at: date.addingTimeInterval(-900))
            state.pause(at: date.addingTimeInterval(-600))
            let anchor = state.session?.startedAt
            let storage = JournalStorage(directory: directory)
            try storage.save(state)
            let model = AppModel(dataDirectory: directory, appVersion: "0.1.9", trackApplicationUsage: false, idleSeconds: { 0 })
            model.beginOnLaunch()
            XCTAssertTrue(model.isPaused)
            XCTAssertFalse(model.isRecording)
            XCTAssertTrue(model.prepareForQuit())
            XCTAssertEqual(try storage.load().pauseDate, state.pauseDate)
            XCTAssertTrue(model.prepareForUpdate(sourceVersion: "0.1.9", targetVersion: "0.2.0"))
            XCTAssertTrue(model.prepareForQuit())
            let updated = AppModel(dataDirectory: directory, appVersion: "0.2.0", trackApplicationUsage: false, idleSeconds: { 0 })
            XCTAssertTrue(updated.isPaused)
            XCTAssertEqual(updated.entries.count, 0)
            XCTAssertTrue(updated.resolvePause(recordGap: true))
            XCTAssertEqual(updated.journal.session?.startedAt, anchor)
            XCTAssertTrue(updated.isRecording)
            XCTAssertTrue(updated.prepareForQuit())
            XCTAssertEqual(updated.entries.count, 1)
            XCTAssertGreaterThan(updated.entries.first?.duration ?? 0, 899)
        }
    }

    func testFailedPauseSaveFreezesMemoryAndFailedResolutionKeepsItFrozen() async throws {
        try await MainActor.run {
            let directory = directory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let model = AppModel(dataDirectory: directory, appVersion: "0.1.9", trackApplicationUsage: false, idleSeconds: { 0 })
            model.startRecording()
            let storage = JournalStorage(directory: directory)
            let intact = try Data(contentsOf: storage.fileURL)
            try Data("invalid journal".utf8).write(to: storage.fileURL)
            model.handleSleep()
            XCTAssertTrue(model.isPaused)
            XCTAssertFalse(model.isRecording)
            let boundary = model.pauseDate
            model.handleWake()
            model.tick(at: Date().addingTimeInterval(86_400))
            XCTAssertEqual(model.pauseDate, boundary)
            XCTAssertFalse(model.resolvePause(recordGap: false))
            XCTAssertTrue(model.isPaused)
            try intact.write(to: storage.fileURL)
            XCTAssertTrue(model.resolvePause(recordGap: false))
            XCTAssertTrue(model.isRecording)
        }
    }

    func testEditorCannotBeReplacedAndDiscardOnlyDeletesAnEmptyPendingEntry() async throws {
        try await MainActor.run {
            let directory = directory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let date = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
            let blank = JournalEntry(start: date.addingTimeInterval(-7_200), end: date.addingTimeInterval(-5_400), createdAt: date)
            let written = JournalEntry(start: date.addingTimeInterval(-5_400), end: date.addingTimeInterval(-3_600), text: "Pending note", createdAt: date)
            let recorded = JournalEntry(start: date.addingTimeInterval(-3_600), end: date.addingTimeInterval(-1_800), text: "Saved", status: .recorded, createdAt: date)
            var state = JournalState()
            state.entries = [blank, written, recorded]
            let storage = JournalStorage(directory: directory)
            try storage.save(state)
            let model = AppModel(dataDirectory: directory, appVersion: "0.1.9", trackApplicationUsage: false, idleSeconds: { 0 })
            model.openEditor(blank)
            let draft = JournalEditorDraft(entryID: blank.id, start: blank.start, end: blank.end, text: "Unsubmitted editor")
            model.editorDraft = draft
            let editorID = model.presentedEditor?.id
            model.openEditor()
            model.openPendingEntry(blank.id)
            XCTAssertEqual(model.presentedEditor?.id, editorID)
            XCTAssertEqual(model.editorDraft, draft)
            XCTAssertNil(model.promptEntryID)
            XCTAssertFalse(model.discardPrompt(id: blank.id))
            XCTAssertTrue(model.discardEditorDraft())
            model.openEditor()
            let unrelated = JournalEditorDraft(entryID: nil, start: date.addingTimeInterval(-900), end: date.addingTimeInterval(-600), text: "Unrelated draft")
            model.editorDraft = unrelated
            XCTAssertFalse(model.discardPrompt(id: written.id))
            XCTAssertFalse(model.discardPrompt(id: recorded.id))
            model.setDraft(id: blank.id, text: "Unsubmitted reminder")
            XCTAssertFalse(model.discardPrompt(id: blank.id))
            model.setDraft(id: blank.id, text: " \n")
            XCTAssertTrue(model.discardPrompt(id: blank.id))
            XCTAssertEqual(model.editorDraft, unrelated)
            XCTAssertEqual(try storage.load().editorDraft, unrelated)
            XCTAssertEqual(model.entries.map(\.id), [written.id, recorded.id])
        }
    }
}
