import Foundation
import XCTest
@testable import JustNowCore

final class CalendarSelectionTests: XCTestCase {
    func testCalendarEditsPreserveUntouchedComponentsAndRejectMissingLocalTimes() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) throws -> Date {
            try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: 17)))
                .addingTimeInterval(0.375)
        }

        let original = try date(2024, 1, 31, 14, 47)
        let leapDay = try XCTUnwrap(CalendarSelection.replacingDay(of: original, with: date(2024, 2, 29), calendar: calendar))
        XCTAssertEqual(leapDay, try date(2024, 2, 29, 14, 47))
        let newYear = try XCTUnwrap(CalendarSelection.replacingDay(of: leapDay, with: date(2025, 1, 1), calendar: calendar))
        XCTAssertEqual(newYear, try date(2025, 1, 1, 14, 47))
        XCTAssertEqual(CalendarSelection.replacingTime(of: leapDay, hour: 23, minute: 59, calendar: calendar), try date(2024, 2, 29, 23, 59))
        XCTAssertEqual(CalendarSelection.replacingTime(of: original, hour: 14, minute: 47, calendar: calendar), original)
        XCTAssertNil(CalendarSelection.replacingTime(of: original, hour: 24, minute: 0, calendar: calendar))
        XCTAssertNil(CalendarSelection.replacingTime(of: original, hour: 0, minute: 60, calendar: calendar))

        let spring = try date(2024, 3, 10, 1, 30)
        XCTAssertNil(CalendarSelection.replacingTime(of: spring, hour: 2, minute: 30, calendar: calendar))
        XCTAssertEqual(CalendarSelection.replacingTime(of: spring, hour: 3, minute: 30, calendar: calendar), try date(2024, 3, 10, 3, 30))
        XCTAssertNil(CalendarSelection.replacingDay(of: try date(2024, 3, 9, 2, 30), with: spring, calendar: calendar))

        let repeated = try date(2024, 11, 3, 1, 30).addingTimeInterval(3_600)
        XCTAssertEqual(CalendarSelection.replacingTime(of: repeated, hour: 1, minute: 30, calendar: calendar), repeated)
        XCTAssertEqual(CalendarSelection.replacingTime(of: repeated, hour: 1, minute: 31, calendar: calendar), repeated.addingTimeInterval(60))

        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        var chinese = Calendar(identifier: .chinese)
        chinese.timeZone = calendar.timeZone
        let leapMonth = try date(2023, 3, 25, 12, 14)
        let regularMonth = try date(2023, 5, 25, 12, 14)
        XCTAssertEqual(chinese.dateComponents([.month], from: leapMonth).isLeapMonth, true)
        XCTAssertEqual(CalendarSelection.replacingDay(of: leapMonth, with: regularMonth, calendar: chinese), regularMonth)
        XCTAssertEqual(CalendarSelection.replacingDay(of: regularMonth, with: leapMonth, calendar: chinese), leapMonth)
    }
}
