import Combine
import Foundation
import Sparkle

@MainActor
final class UpdateController: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published private(set) var canCheckForUpdates = false
    let isConfigured: Bool
    var onBeforeRelaunch: ((String) -> Bool)?
    var onCancel: (() -> Void)?
    var onError: ((String) -> Void)?

    private let configurationIssue: String?
    private var controller: SPUStandardUpdaterController?
    private var started = false
    private var targetVersion: String?
    private var preparedVersion: String?

    init(enabled: Bool = true) {
        let bundle = Bundle.main
        let feed = (bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String).flatMap { URL(string: $0) }
        let key = (bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String).flatMap { Data(base64Encoded: $0) }
        let localFeedAllowed = bundle.object(forInfoDictionaryKey: "JustNowAllowLocalUpdateFeed") as? Bool == true
        let secureFeed = feed?.scheme == "https" && !(feed?.host?.isEmpty ?? true)
        let localFeed = localFeedAllowed && feed?.scheme == "http" && ["127.0.0.1", "localhost"].contains(feed?.host ?? "")
        if !enabled {
            configurationIssue = "Updates are disabled in previews."
        } else if (!secureFeed && !localFeed) || key?.count != 32 {
            configurationIssue = "This build does not have a signed update feed configured."
        } else {
            configurationIssue = nil
        }
        isConfigured = configurationIssue == nil
        super.init()
        if isConfigured {
            let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
            self.controller = controller
            controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheckForUpdates)
        }
    }

    func start() {
        guard !started, let controller else { return }
        do {
            try controller.updater.start()
            started = true
        } catch {
            onError?(error.localizedDescription)
        }
    }

    func checkForUpdates() {
        guard let controller else {
            onError?(configurationIssue ?? "Updates are unavailable.")
            return
        }
        start()
        guard started else { return }
        controller.checkForUpdates(nil)
    }

    func cancelPreparedUpdate() {
        preparedVersion = nil
        onCancel?()
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        targetVersion = item.versionString
    }

    func updaterShouldRelaunchApplication(_ updater: SPUUpdater) -> Bool {
        // Sparkle aborts the installation request when this delegate returns false.
        guard let version = targetVersion, let onBeforeRelaunch else {
            onError?("The update could not safely prepare the current recording for restart.")
            return false
        }
        if preparedVersion == version { return true }
        guard onBeforeRelaunch(version) else {
            cancelPreparedUpdate()
            return false
        }
        preparedVersion = version
        return true
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        targetVersion = item.versionString
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        targetVersion = nil
        cancelPreparedUpdate()
    }
}
