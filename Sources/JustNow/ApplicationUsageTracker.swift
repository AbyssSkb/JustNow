import AppKit
import JustNowCore

@MainActor
final class ApplicationUsageTracker {
    struct Application: Equatable, Sendable {
        var bundleIdentifier: String?
        var name: String
    }

    enum PauseReason: Hashable { case systemSleep, screenSleep, inactiveSession }

    private(set) var isTracking = false
    private var activities: [ApplicationActivity] = []
    private var current: ApplicationActivity?
    private var lastEventDate: Date?
    private var pauses: Set<PauseReason> = []
    private let frontmostApplication: () -> Application?
    private let clock: () -> Date
    private var observation: NSKeyValueObservation?
    private var observers: [NSObjectProtocol] = []
    private let notificationCenter = NSWorkspace.shared.notificationCenter

    init(frontmostApplication: (() -> Application?)? = nil, observeWorkspace: Bool = true,
         clock: @escaping () -> Date = Date.init) {
        self.frontmostApplication = frontmostApplication ?? { Self.application(NSWorkspace.shared.frontmostApplication) }
        self.clock = clock
        guard observeWorkspace else { return }
        observation = NSWorkspace.shared.observe(\.frontmostApplication, options: [.new]) { [weak self] _, change in
            let application = change.newValue ?? nil
            if Thread.isMainThread {
                MainActor.assumeIsolated { self?.frontmostDidChange(application) }
            } else {
                DispatchQueue.main.async { self?.frontmostDidChange(application) }
            }
        }
        // ponytail: documented sleep/session signals exclude these gaps; a locked but awake screen is not an inactivity detector.
        let notifications: [(Notification.Name, PauseReason, Bool)] = [
            (NSWorkspace.willSleepNotification, .systemSleep, true),
            (NSWorkspace.didWakeNotification, .systemSleep, false),
            (NSWorkspace.screensDidSleepNotification, .screenSleep, true),
            (NSWorkspace.screensDidWakeNotification, .screenSleep, false),
            (NSWorkspace.sessionDidResignActiveNotification, .inactiveSession, true),
            (NSWorkspace.sessionDidBecomeActiveNotification, .inactiveSession, false)
        ]
        for (name, reason, paused) in notifications {
            observers.append(notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.setPaused(paused, for: reason, at: self.clock())
                }
            })
        }
    }

    deinit {
        observation?.invalidate()
        for observer in observers { notificationCenter.removeObserver(observer) }
    }

    func start(at date: Date) {
        guard !isTracking, eventDate(date) != nil else { return }
        isTracking = true
        if pauses.isEmpty { recordSwitch(to: frontmostApplication(), at: date) }
    }

    func stop(at date: Date) {
        guard isTracking, let date = eventDate(date) else { return }
        closeCurrent(at: date)
        isTracking = false
    }

    func snapshot(at date: Date) -> [ApplicationActivity] {
        guard date.timeIntervalSince1970.isFinite else { return [] }
        var result = activities.compactMap { activity -> ApplicationActivity? in
            guard activity.start < date else { return nil }
            var clipped = activity
            clipped.end = min(activity.end, date)
            return clipped.end > clipped.start ? clipped : nil
        }
        if var current, date > current.start {
            current.end = date
            result.append(current)
        }
        return result
    }

    // Only acknowledge after the journal has been saved; failed saves can retry the same spans.
    func acknowledge(through date: Date) {
        guard date.timeIntervalSince1970.isFinite else { return }
        lastEventDate = max(lastEventDate ?? date, date)
        activities = activities.compactMap { activity in
            guard activity.end > date else { return nil }
            var remainder = activity
            remainder.start = max(activity.start, date)
            return remainder
        }
        if let start = current?.start, date > start { current?.start = date }
    }

    func recordSwitch(to application: Application?, at date: Date) {
        guard isTracking, pauses.isEmpty, let date = eventDate(date) else { return }
        if let application, let current,
           current.bundleIdentifier == application.bundleIdentifier, current.name == application.name { return }
        closeCurrent(at: date)
        if let application {
            current = ApplicationActivity(bundleIdentifier: application.bundleIdentifier, name: application.name,
                                          start: date, end: date)
        }
    }

    func setPaused(_ paused: Bool, for reason: PauseReason, at date: Date) {
        guard date.timeIntervalSince1970.isFinite else { return }
        let wasPaused = !pauses.isEmpty
        if paused { pauses.insert(reason) } else { pauses.remove(reason) }
        guard isTracking, wasPaused != !pauses.isEmpty, let date = eventDate(date) else { return }
        if pauses.isEmpty {
            recordSwitch(to: frontmostApplication(), at: date)
        } else {
            closeCurrent(at: date)
        }
    }

    private func closeCurrent(at date: Date) {
        if var current, date > current.start {
            current.end = date
            activities.append(current)
        }
        current = nil
    }

    private func frontmostDidChange(_ app: NSRunningApplication?) {
        guard isTracking else { return }
        recordSwitch(to: Self.application(app), at: clock())
    }

    private func eventDate(_ date: Date) -> Date? {
        guard date.timeIntervalSince1970.isFinite else { return nil }
        let date = max(lastEventDate ?? date, date)
        lastEventDate = date
        return date
    }

    nonisolated private static func application(_ app: NSRunningApplication?) -> Application? {
        guard let app else { return nil }
        return Application(bundleIdentifier: app.bundleIdentifier, name: app.localizedName ?? app.bundleIdentifier ?? "Application")
    }
}
