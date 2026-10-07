import Foundation

public struct ApplicationActivity: Codable, Equatable, Sendable {
    public var bundleIdentifier: String?
    public var name: String
    public var start: Date
    public var end: Date

    public init(bundleIdentifier: String? = nil, name: String, start: Date, end: Date) {
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.start = start
        self.end = end
    }

    var identity: String { bundleIdentifier.map { "bundle:\($0)" } ?? "name:\(name)" }
    var isValid: Bool {
        start.timeIntervalSinceReferenceDate.isFinite && end.timeIntervalSinceReferenceDate.isFinite &&
        start < end && end.timeIntervalSince(start).isFinite && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public struct ApplicationUsage: Codable, Equatable, Sendable {
    public var bundleIdentifier: String?
    public var name: String
    public var seconds: TimeInterval

    public init(bundleIdentifier: String? = nil, name: String, seconds: TimeInterval) {
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.seconds = seconds
    }

    var identity: String { bundleIdentifier.map { "bundle:\($0)" } ?? "name:\(name)" }
}

public struct ApplicationUsageSummary: Codable, Equatable, Sendable {
    public var start: Date
    public var end: Date
    public var applications: [ApplicationUsage]
    public var duration: TimeInterval { end.timeIntervalSince(start) }
    public var observedSeconds: TimeInterval { applications.reduce(0) { $0 + $1.seconds } }

    public init(start: Date, end: Date, applications: [ApplicationUsage]) {
        self.start = start
        self.end = end
        self.applications = applications
    }

    init(start: Date, end: Date, activity: [ApplicationActivity]) {
        var usage: [String: ApplicationUsage] = [:]
        for span in activity {
            let seconds = min(span.end, end).timeIntervalSince(max(span.start, start))
            guard seconds > 0 else { continue }
            if var existing = usage[span.identity] {
                existing.seconds += seconds
                usage[span.identity] = existing
            } else {
                usage[span.identity] = ApplicationUsage(bundleIdentifier: span.bundleIdentifier, name: span.name, seconds: seconds)
            }
        }
        self.init(start: start, end: end, applications: usage.values.sorted {
            $0.seconds == $1.seconds ? $0.name < $1.name : $0.seconds > $1.seconds
        })
    }

    func validate() throws {
        guard start.timeIntervalSinceReferenceDate.isFinite, end.timeIntervalSinceReferenceDate.isFinite,
              duration.isFinite, duration > 0, observedSeconds.isFinite, observedSeconds <= duration + 0.000_001,
              Set(applications.map(\.identity)).count == applications.count,
              applications.allSatisfy({ $0.seconds.isFinite && $0.seconds > 0 && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        else { throw JournalError.invalidApplicationUsage }
    }
}
