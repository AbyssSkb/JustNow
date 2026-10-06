import Foundation

public enum CalendarSelection {
    public static func replacingDay(of date: Date, with day: Date, calendar: Calendar = .current) -> Date? {
        var components = calendar.dateComponents([.era, .year, .month, .day, .hour, .minute, .second], from: date)
        let selected = calendar.dateComponents([.era, .year, .month, .day], from: day)
        components.era = selected.era
        components.year = selected.year
        components.month = selected.month
        components.day = selected.day
        components.isLeapMonth = selected.isLeapMonth
        return replacingComponents(of: date, with: components, calendar: calendar)
    }

    public static func replacingTime(of date: Date, hour: Int, minute: Int, calendar: Calendar = .current) -> Date? {
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        var components = calendar.dateComponents([.era, .year, .month, .day, .hour, .minute, .second], from: date)
        components.hour = hour
        components.minute = minute
        return replacingComponents(of: date, with: components, calendar: calendar)
    }

    private static func replacingComponents(of date: Date, with components: DateComponents, calendar: Calendar) -> Date? {
        let units: Set<Calendar.Component> = [.era, .year, .month, .day, .hour, .minute, .second]
        let original = calendar.dateComponents(units, from: date)
        if components == original { return date }
        // Foundation normalizes missing local times during daylight-saving transitions.
        // Require the requested wall-clock components to round-trip instead.
        guard var candidate = calendar.date(from: components),
              calendar.dateComponents(units, from: candidate) == components else { return nil }
        let offset = calendar.timeZone.secondsFromGMT(for: date)
        let sameOffset = candidate.addingTimeInterval(Double(calendar.timeZone.secondsFromGMT(for: candidate) - offset))
        if calendar.timeZone.secondsFromGMT(for: sameOffset) == offset,
           calendar.dateComponents(units, from: sameOffset) == components {
            candidate = sameOffset
        }
        let seconds = date.timeIntervalSinceReferenceDate
        return candidate.addingTimeInterval(seconds - floor(seconds))
    }
}
