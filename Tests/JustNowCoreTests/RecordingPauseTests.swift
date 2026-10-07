import Foundation
import XCTest
@testable import JustNowCore

final class RecordingPauseTests: XCTestCase {
    private let origin = Date(timeIntervalSince1970: 1_800_000_000)
    private func at(_ minutes: Double) -> Date { origin.addingTimeInterval(minutes * 60) }
    private func pausedState() -> JournalState {
        var state = JournalState()
        state.start(at: at(0))
        state.appendApplicationActivity([ApplicationActivity(name: "Code", start: at(0), end: at(42))])
        state.pause(at: at(42))
        return state
    }

    func testOvernightPauseFreezesHeartbeatIntervalsAndApplicationCapture() throws {
        var state = pausedState()
        XCTAssertTrue(state.isRecording)
        XCTAssertEqual(state.pauseDate, at(42))
        XCTAssertEqual(state.entries.map(\.end), [at(30)])
        let frozen = state
        XCTAssertTrue(state.advance(to: at(1_440)).isEmpty)
        state.appendApplicationActivity([ApplicationActivity(name: "Safari", start: at(42), end: at(1_440))])
        XCTAssertTrue(state.pause(at: at(1_440)).isEmpty)
        XCTAssertTrue(state.recoverInterruptedSession().isEmpty)
        XCTAssertEqual(state, frozen)
        try state.validate()
    }

    func testRecordingTheGapKeepsOriginalIntervalAnchorAndHonestUsageGaps() throws {
        var state = pausedState()
        XCTAssertEqual(state.resume(at: at(95), recordGap: true).count, 2)
        XCTAssertNil(state.pauseDate)
        XCTAssertEqual(state.session?.startedAt, at(0))
        XCTAssertEqual(state.session?.segmentStartedAt, at(90))
        XCTAssertEqual(state.session?.lastHeartbeatAt, at(95))
        XCTAssertEqual(state.entries.map(\.end), [at(30), at(60), at(90)])
        XCTAssertEqual(state.entries[1].applicationUsage?.duration, 1_800)
        XCTAssertEqual(state.entries[1].applicationUsage?.observedSeconds, 720)
        XCTAssertEqual(state.entries[2].applicationUsage?.observedSeconds, 0)
        XCTAssertTrue(state.advance(to: at(95)).isEmpty)
        try state.validate()
    }

    func testDiscardingTheGapClosesTheFrozenTailAndStartsANewAnchor() throws {
        var state = pausedState()
        XCTAssertEqual(state.resume(at: at(95), recordGap: false).count, 1)
        XCTAssertNil(state.pauseDate)
        XCTAssertEqual(state.entries.map(\.start), [at(0), at(30)])
        XCTAssertEqual(state.entries.map(\.end), [at(30), at(42)])
        XCTAssertEqual(state.entries[1].applicationUsage?.observedSeconds, 720)
        XCTAssertEqual(state.session?.startedAt, at(95))
        XCTAssertEqual(state.session?.segmentStartedAt, at(95))
        XCTAssertEqual(state.advance(to: at(125)).count, 1)
        XCTAssertEqual(state.entries.last?.start, at(95))
        XCTAssertEqual(state.entries.last?.end, at(125))
        try state.validate()
    }

    func testManualStopUsesFrozenBoundaryAndClearsPauseMarker() throws {
        var state = pausedState()
        XCTAssertEqual(state.stop(at: at(1_440)).count, 1)
        XCTAssertEqual(state.entries.map(\.end), [at(30), at(42)])
        XCTAssertNil(state.session)
        XCTAssertNil(state.pauseDate)
        XCTAssertTrue(state.stop(at: at(1_440)).isEmpty)
        XCTAssertTrue(state.start(at: at(1_440)))
        XCTAssertNil(state.pauseDate)
        try state.validate()
    }

    func testPausedJournalRoundTripAndUpdateResumeDoNotFillTheGap() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("justnow-pause-tests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = JournalStorage(directory: directory)
        var state = pausedState()
        state.preferences.autoStartRecording = false
        state.preferences.pauseWhenInactive = true
        state.updateContinuation = AppUpdateContinuation(preparedAt: at(43), sourceVersion: "0.1.9", targetVersion: "0.2.0")
        try storage.save(state)
        var restored = try storage.load()
        XCTAssertEqual(restored, state)
        XCTAssertNotNil(restored.consumeUpdateContinuation(at: at(44), appVersion: "0.2.0"))
        XCTAssertEqual(restored.pauseDate, at(42))
        XCTAssertEqual(restored.session?.lastHeartbeatAt, at(42))
        XCTAssertEqual(restored.entries.count, 1)
        XCTAssertTrue(restored.recoverInterruptedSession().isEmpty)
        XCTAssertEqual(restored.session, state.session)
        XCTAssertNil(restored.updateContinuation)
        try restored.validate()

        let oldJSON = """
        {"version":1,"entries":[],"preferences":{"intervalMinutes":30,"playSound":true,"appearance":"system","language":"system","completedOnboarding":true}}
        """
        let old = try JSONDecoder().decode(JournalState.self, from: Data(oldJSON.utf8))
        XCTAssertNil(old.pauseDate)
        XCTAssertNil(old.preferences.autoStartRecording)
        XCTAssertNil(old.preferences.pauseWhenInactive)
        try old.validate()
    }

    func testClockRegressionCannotResumeOrMoveTheFrozenBoundaryBackwards() throws {
        var state = JournalState()
        state.start(at: at(0))
        state.advance(to: at(20))
        state.pause(at: at(19))
        XCTAssertEqual(state.pauseDate, at(20))
        let frozen = state
        XCTAssertTrue(state.resume(at: at(19), recordGap: true).isEmpty)
        XCTAssertEqual(state, frozen)
        XCTAssertTrue(state.resume(at: at(19), recordGap: false).isEmpty)
        XCTAssertEqual(state, frozen)
        XCTAssertTrue(state.resume(at: Date(timeIntervalSinceReferenceDate: .infinity), recordGap: false).isEmpty)
        XCTAssertEqual(state, frozen)
        state.pauseDate = at(21)
        XCTAssertThrowsError(try state.validate()) { XCTAssertEqual($0 as? JournalError, .invalidDates) }
        state.session = nil
        state.pauseDate = at(20)
        XCTAssertThrowsError(try state.validate()) { XCTAssertEqual($0 as? JournalError, .invalidDates) }
    }
}
