import Foundation
import XCTest
@testable import JustNowCore

final class ApplicationUsageTests: XCTestCase {
    private let origin = Date(timeIntervalSince1970: 1_800_000_000)
    private func at(_ minutes: Double) -> Date { origin.addingTimeInterval(minutes * 60) }
    private func activity(_ name: String, _ start: Double, _ end: Double, bundle: String? = nil) -> ApplicationActivity {
        ApplicationActivity(bundleIdentifier: bundle, name: name, start: at(start), end: at(end))
    }

    func testMultipleApplicationsAreClippedAtEveryBoundaryAndPartialStop() throws {
        var state = JournalState()
        state.start(at: at(0))
        state.appendApplicationActivity([activity("Safari", 0, 20), activity("Code", 20, 40), activity("Safari", 40, 65)])
        XCTAssertEqual(state.advance(to: at(65)).count, 2)
        XCTAssertEqual(state.entries[0].applicationUsage?.applications, [
            ApplicationUsage(name: "Safari", seconds: 1_200), ApplicationUsage(name: "Code", seconds: 600)
        ])
        XCTAssertEqual(state.entries[1].applicationUsage?.applications, [
            ApplicationUsage(name: "Safari", seconds: 1_200), ApplicationUsage(name: "Code", seconds: 600)
        ])
        XCTAssertEqual(state.session?.applicationActivity, [activity("Safari", 60, 65)])
        state.appendApplicationActivity([activity("Safari", 65, 70)])
        XCTAssertEqual(state.stop(at: at(70)).count, 1)
        let partial = try XCTUnwrap(state.entries.last?.applicationUsage)
        XCTAssertEqual(partial.start, at(60))
        XCTAssertEqual(partial.end, at(70))
        XCTAssertEqual(partial.applications, [ApplicationUsage(name: "Safari", seconds: 600)])
        XCTAssertNil(state.session)
        XCTAssertTrue(state.stop(at: at(70)).isEmpty)
        try state.validate()
    }

    func testUnobservedGapsStayInThePercentageDenominator() throws {
        var state = JournalState()
        state.start(at: at(0))
        state.appendApplicationActivity([
            activity("Safari", 0, 10, bundle: "com.apple.Safari"),
            activity("Safari Technology Preview", 20, 25, bundle: "com.apple.Safari")
        ])
        state.stop(at: at(30))
        let summary = try XCTUnwrap(state.entries.first?.applicationUsage)
        XCTAssertEqual(summary.duration, 1_800)
        XCTAssertEqual(summary.observedSeconds, 900)
        XCTAssertEqual(summary.applications.count, 1)
        XCTAssertEqual(try XCTUnwrap(summary.applications.first).seconds / summary.duration, 0.5)
        try state.validate()

        var unobserved = JournalState()
        unobserved.start(at: at(0))
        unobserved.stop(at: at(30))
        XCTAssertEqual(unobserved.entries.first?.applicationUsage?.applications, [])
        XCTAssertEqual(unobserved.entries.first?.applicationUsage?.observedSeconds, 0)
    }

    func testReplayedSamplesCoalesceWithoutCountingTwiceAcrossSavedBoundaries() throws {
        var state = JournalState()
        state.start(at: at(0))
        let first = activity("Code", -5, 10)
        state.appendApplicationActivity([first, first])
        state.appendApplicationActivity([activity("Code", 8, 20)])
        XCTAssertEqual(state.session?.applicationActivity, [activity("Code", 0, 20)])
        state.advance(to: at(30))
        let saved = try XCTUnwrap(state.entries.first?.applicationUsage)
        state.appendApplicationActivity([first, activity("Code", 8, 20), activity("Code", 20, 40)])
        XCTAssertEqual(state.session?.applicationActivity, [activity("Code", 30, 40)])
        XCTAssertEqual(state.entries.first?.applicationUsage, saved)
        state.stop(at: at(40))
        XCTAssertEqual(state.entries[0].applicationUsage?.observedSeconds, 1_200)
        XCTAssertEqual(state.entries[1].applicationUsage?.observedSeconds, 600)
        try state.validate()
    }

    func testOldJournalsDecodeAndNewActivitySurvivesUpdateReload() throws {
        let oldJSON = """
        {"version":1,"entries":[{"id":"00000000-0000-0000-0000-000000000001","start":1800000000,"end":1800001800,"text":"","status":"pending","createdAt":1800001800}],"preferences":{"intervalMinutes":30,"playSound":true,"appearance":"system","language":"system","completedOnboarding":true}}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let old = try decoder.decode(JournalState.self, from: Data(oldJSON.utf8))
        XCTAssertNil(old.preferences.captureApplicationUsage)
        XCTAssertNil(old.entries.first?.applicationUsage)
        XCTAssertNil(old.editorDraft)
        try old.validate()

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("justnow-usage-tests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = JournalStorage(directory: directory)
        var state = JournalState()
        state.start(at: at(0))
        state.appendApplicationActivity([activity("Code", 0, 29)])
        state.editorDraft = JournalEditorDraft(entryID: nil, start: at(-5), end: at(-10), text: "Temporary invalid range is still a draft")
        state.updateContinuation = AppUpdateContinuation(preparedAt: at(29), sourceVersion: "0.1.8", targetVersion: "0.1.9")
        try storage.save(state)
        var restored = try storage.load()
        XCTAssertEqual(restored, state)
        XCTAssertNotNil(restored.consumeUpdateContinuation(at: at(31), appVersion: "0.1.9"))
        XCTAssertEqual(restored.session?.startedAt, at(0))
        XCTAssertEqual(restored.entries.first?.applicationUsage?.observedSeconds, 1_740)
        restored.appendApplicationActivity([activity("Safari", 31, 32)])
        restored.stop(at: at(32))
        XCTAssertEqual(restored.entries[1].applicationUsage?.duration, 120)
        XCTAssertEqual(restored.entries[1].applicationUsage?.observedSeconds, 60)
        try restored.validate()
    }

    func testEditingEntryTimesDoesNotInventAChangedCaptureWindow() throws {
        var state = JournalState()
        state.start(at: at(0))
        state.appendApplicationActivity([activity("Code", 0, 20)])
        let id = try XCTUnwrap(state.stop(at: at(30)).first)
        let original = state.entries[0].applicationUsage
        try state.updateEntry(id: id, text: "Worked on the editor", start: at(5), end: at(25))
        XCTAssertEqual(state.entries[0].applicationUsage, original)
        try state.validate()

        var disabled = JournalState()
        disabled.preferences.captureApplicationUsage = false
        disabled.start(at: at(0))
        disabled.stop(at: at(30))
        XCTAssertNil(disabled.entries.first?.applicationUsage)
        try disabled.insertEntry(start: at(30), end: at(40), text: "Manual note")
        XCTAssertNil(disabled.entries.last?.applicationUsage)
    }

    func testCorruptDurationsAndOverlappingActivityAreRejected() throws {
        var state = JournalState()
        state.entries = [JournalEntry(start: at(0), end: at(30), applicationUsage:
            ApplicationUsageSummary(start: at(0), end: at(30), applications: [ApplicationUsage(name: "Code", seconds: 1_801)]))]
        XCTAssertThrowsError(try state.validate()) { XCTAssertEqual($0 as? JournalError, .invalidApplicationUsage) }
        state.entries[0].applicationUsage?.applications = [ApplicationUsage(name: "Code", seconds: .nan)]
        XCTAssertThrowsError(try state.validate())
        state.entries[0].applicationUsage?.applications = [ApplicationUsage(name: "Code", seconds: 10), ApplicationUsage(name: "Code", seconds: 10)]
        XCTAssertThrowsError(try state.validate())
        state.entries = []
        state.session = RecordingSession(startedAt: at(0), segmentStartedAt: at(0), lastHeartbeatAt: at(20), intervalMinutes: 30,
                                         applicationActivity: [activity("Code", 0, 15), activity("Safari", 10, 20)])
        XCTAssertThrowsError(try state.validate()) { XCTAssertEqual($0 as? JournalError, .invalidApplicationUsage) }
        state.session?.applicationActivity = []
        state.appendApplicationActivity([activity("Code", 20, 10), activity("", 0, 10), activity("Safari", 0, 10)])
        XCTAssertEqual(state.session?.applicationActivity, [activity("Safari", 0, 10)])
        try state.validate()
    }
}
