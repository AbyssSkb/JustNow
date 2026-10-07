import Sparkle
import XCTest
@testable import JustNow

final class UpdateControllerTests: XCTestCase {
    func testMissingConfigurationDoesNotStartOrPrepareAnUpdate() async {
        await MainActor.run {
            let updates = UpdateController()
            var errors: [String] = []
            var preparations = 0
            updates.onError = { errors.append($0) }
            updates.onBeforeRelaunch = { _ in preparations += 1; return true }
            XCTAssertFalse(updates.isConfigured)
            updates.start()
            XCTAssertFalse(updates.canCheckForUpdates)
            XCTAssertTrue(errors.isEmpty)
            updates.checkForUpdates()
            XCTAssertEqual(errors.count, 1)
            XCTAssertEqual(preparations, 0)
            XCTAssertFalse(updates.canCheckForUpdates)
        }
    }

    func testRelaunchWithoutAnUpdateVersionIsRejected() async {
        await MainActor.run {
            let updates = UpdateController(enabled: false)
            let updater = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil).updater
            var errors: [String] = []
            var preparations = 0
            updates.onError = { errors.append($0) }
            updates.onBeforeRelaunch = { _ in preparations += 1; return true }
            XCTAssertFalse(updates.updaterShouldRelaunchApplication(updater))
            XCTAssertEqual(errors.count, 1)
            XCTAssertEqual(preparations, 0)
        }
    }

    func testFailedCheckpointVetoesRelaunchAndCancellationAllowsRetry() async throws {
        try await MainActor.run {
            let updates = UpdateController(enabled: false)
            let updater = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil).updater
            // This test fixture only needs versionString, independent of application or system state.
            let item = try XCTUnwrap(SUAppcastItem(dictionary: [
                "sparkle:version": "0.1.9",
                "enclosure": ["url": "https://example.invalid/JustNow-0.1.9.zip", "length": "1"]
            ]))
            var checkpointSucceeds = false
            var preparedVersions: [String] = []
            var cancellations = 0
            updates.onBeforeRelaunch = { preparedVersions.append($0); return checkpointSucceeds }
            updates.onCancel = { cancellations += 1 }
            updates.updater(updater, didFindValidUpdate: item)
            XCTAssertFalse(updates.updaterShouldRelaunchApplication(updater))
            XCTAssertEqual(preparedVersions, ["0.1.9"])
            XCTAssertEqual(cancellations, 1)

            checkpointSucceeds = true
            XCTAssertTrue(updates.updaterShouldRelaunchApplication(updater))
            XCTAssertTrue(updates.updaterShouldRelaunchApplication(updater))
            XCTAssertEqual(preparedVersions, ["0.1.9", "0.1.9"])
            updates.cancelPreparedUpdate()
            XCTAssertEqual(cancellations, 2)
            XCTAssertTrue(updates.updaterShouldRelaunchApplication(updater))
            XCTAssertEqual(preparedVersions, ["0.1.9", "0.1.9", "0.1.9"])

            updates.updater(updater, didFinishUpdateCycleFor: .updates, error: nil)
            XCTAssertEqual(cancellations, 3)
            XCTAssertFalse(updates.updaterShouldRelaunchApplication(updater))
            XCTAssertEqual(preparedVersions.count, 3)
        }
    }
}
