import Foundation
import XCTest
import JustNowCore
@testable import JustNow

final class ApplicationUsageTrackerTests: XCTestCase {
    private let editor = ApplicationUsageTracker.Application(bundleIdentifier: "test.editor", name: "Editor")
    private let browser = ApplicationUsageTracker.Application(bundleIdentifier: "test.browser", name: "Browser")

    private func at(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

    func testOnlyExplicitRecordingCapturesAndSwitchesSplitExactDurations() async {
        await MainActor.run {
            var queries = 0
            let tracker = ApplicationUsageTracker(frontmostApplication: { queries += 1; return self.editor }, observeWorkspace: false)
            tracker.recordSwitch(to: browser, at: at(90))
            XCTAssertTrue(tracker.snapshot(at: at(100)).isEmpty)
            XCTAssertEqual(queries, 0)
            tracker.start(at: at(100))
            tracker.start(at: at(105))
            tracker.recordSwitch(to: editor, at: at(110))
            tracker.recordSwitch(to: browser, at: at(120))
            tracker.stop(at: at(150))
            tracker.recordSwitch(to: editor, at: at(160))
            XCTAssertFalse(tracker.isTracking)
            XCTAssertEqual(queries, 1)
            let result = tracker.snapshot(at: at(200))
            XCTAssertEqual(result.map(\.name), ["Editor", "Browser"])
            XCTAssertEqual(result.map { $0.end.timeIntervalSince($0.start) }, [20, 30])
            XCTAssertEqual(result.map(\.start), [at(100), at(120)])
        }
    }

    func testSnapshotsRetainFailedSavesAndAcknowledgementKeepsOnlyUnsavedRemainder() async {
        await MainActor.run {
            let tracker = ApplicationUsageTracker(frontmostApplication: { self.editor }, observeWorkspace: false)
            tracker.start(at: at(100))
            tracker.recordSwitch(to: browser, at: at(120))
            let failed = tracker.snapshot(at: at(140))
            XCTAssertEqual(tracker.snapshot(at: at(140)), failed)
            XCTAssertEqual(failed.map { $0.end.timeIntervalSince($0.start) }, [20, 20])
            tracker.acknowledge(through: at(130))
            tracker.acknowledge(through: at(125))
            let remainder = tracker.snapshot(at: at(140))
            XCTAssertEqual(remainder.count, 1)
            XCTAssertEqual(remainder.first?.start, at(130))
            XCTAssertEqual(remainder.first?.end, at(140))
            tracker.stop(at: at(150))
            tracker.acknowledge(through: at(150))
            XCTAssertTrue(tracker.snapshot(at: at(200)).isEmpty)
            tracker.start(at: at(170))
            XCTAssertEqual(tracker.snapshot(at: at(180)).first?.start, at(170))
        }
    }

    func testIndependentPauseGatesExcludeGapsAndResumeActualFrontmostApp() async {
        await MainActor.run {
            var application = editor
            let tracker = ApplicationUsageTracker(frontmostApplication: { application }, observeWorkspace: false)
            tracker.start(at: at(100))
            tracker.setPaused(true, for: .screenSleep, at: at(110))
            tracker.setPaused(true, for: .systemSleep, at: at(120))
            application = browser
            tracker.recordSwitch(to: browser, at: at(130))
            tracker.setPaused(false, for: .systemSleep, at: at(150))
            XCTAssertEqual(tracker.snapshot(at: at(160)).map { $0.end.timeIntervalSince($0.start) }, [10])
            tracker.setPaused(true, for: .inactiveSession, at: at(170))
            tracker.setPaused(false, for: .screenSleep, at: at(180))
            tracker.setPaused(false, for: .inactiveSession, at: at(200))
            tracker.stop(at: at(230))
            let result = tracker.snapshot(at: at(250))
            XCTAssertEqual(result.map(\.name), ["Editor", "Browser"])
            XCTAssertEqual(result.map(\.start), [at(100), at(200)])
            XCTAssertEqual(result.map { $0.end.timeIntervalSince($0.start) }, [10, 30])
        }
    }

    func testStopDuringPauseDoesNotRestartAndNoFrontmostLeavesAnUncountedGap() async {
        await MainActor.run {
            var application: ApplicationUsageTracker.Application? = editor
            let tracker = ApplicationUsageTracker(frontmostApplication: { application }, observeWorkspace: false)
            tracker.start(at: at(100))
            tracker.setPaused(true, for: .systemSleep, at: at(110))
            tracker.stop(at: at(120))
            tracker.setPaused(false, for: .systemSleep, at: at(130))
            XCTAssertFalse(tracker.isTracking)
            application = nil
            tracker.start(at: at(140))
            tracker.recordSwitch(to: browser, at: at(160))
            tracker.recordSwitch(to: nil, at: at(180))
            tracker.stop(at: at(200))
            let result = tracker.snapshot(at: at(220))
            XCTAssertEqual(result.map(\.name), ["Editor", "Browser"])
            XCTAssertEqual(result.map { $0.end.timeIntervalSince($0.start) }, [10, 20])
        }
    }

    func testClockMovesBackWithoutNegativeOrOverlappingSpans() async {
        await MainActor.run {
            let tracker = ApplicationUsageTracker(frontmostApplication: { self.editor }, observeWorkspace: false)
            tracker.start(at: at(100))
            tracker.recordSwitch(to: browser, at: at(120))
            tracker.acknowledge(through: at(130))
            tracker.recordSwitch(to: editor, at: at(110))
            XCTAssertTrue(tracker.snapshot(at: at(125)).isEmpty)
            tracker.stop(at: at(150))
            let result = tracker.snapshot(at: at(160))
            XCTAssertEqual(result.count, 1)
            XCTAssertEqual(result.first?.name, "Editor")
            XCTAssertEqual(result.first?.start, at(130))
            XCTAssertEqual(result.first?.end, at(150))
            tracker.start(at: Date(timeIntervalSince1970: .nan))
            XCTAssertFalse(tracker.isTracking)
            XCTAssertTrue(tracker.snapshot(at: Date(timeIntervalSince1970: .infinity)).isEmpty)
        }
    }
}
