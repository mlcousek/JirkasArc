// EventCountdownTests.swift
//
// add-training-shortcuts-and-widgets (design D7): the countdown widget's
// day arithmetic. A day is a calendar day -- so the time of day never
// matters, a DST night is not a day more or less, and the number changes
// exactly at midnight. A fixed calendar and time zone (Europe/Prague, the
// zone the vault's synthetic 2030 season uses), synthetic dates only.

import XCTest
@testable import FoodLogCore

final class EventCountdownTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    // MARK: State

    func testDaysAheadAreWholeCalendarDays() {
        XCTAssertEqual(EventCountdown.state(on: date(2030, 1, 1), eventDate: date(2030, 5, 1), calendar: calendar), .upcoming(days: 120))
        XCTAssertEqual(EventCountdown.state(on: date(2030, 6, 10), eventDate: date(2030, 6, 13), calendar: calendar), .upcoming(days: 3))
    }

    func testTheTimeOfDayNeverMatters() {
        // Five minutes before midnight to five minutes after: tomorrow.
        XCTAssertEqual(EventCountdown.state(on: date(2030, 6, 10, 23, 55), eventDate: date(2030, 6, 11, 0, 5), calendar: calendar), .upcoming(days: 1))
        // Early morning to late evening of the same day: today.
        XCTAssertEqual(EventCountdown.state(on: date(2030, 6, 10, 0, 5), eventDate: date(2030, 6, 10, 23, 55), calendar: calendar), .today)
        XCTAssertEqual(EventCountdown.state(on: date(2030, 6, 10, 23, 55), eventDate: date(2030, 6, 10, 0, 5), calendar: calendar), .today)
    }

    func testAfterTheEvent() {
        XCTAssertEqual(EventCountdown.state(on: date(2030, 6, 11, 0, 5), eventDate: date(2030, 6, 10, 23, 55), calendar: calendar), .past(days: 1))
        XCTAssertEqual(EventCountdown.state(on: date(2030, 6, 20), eventDate: date(2030, 6, 10), calendar: calendar), .past(days: 10))
    }

    func testADaylightSavingNightIsOneDay() {
        // Spring forward in Prague: 2030-03-31 has 23 hours.
        XCTAssertEqual(EventCountdown.state(on: date(2030, 3, 30), eventDate: date(2030, 4, 1), calendar: calendar), .upcoming(days: 2))
        XCTAssertEqual(EventCountdown.state(on: date(2030, 3, 30, 23, 30), eventDate: date(2030, 3, 31, 3, 30), calendar: calendar), .upcoming(days: 1))
        // Fall back: 2030-10-27 has 25 hours.
        XCTAssertEqual(EventCountdown.state(on: date(2030, 10, 26, 23, 30), eventDate: date(2030, 10, 28, 0, 30), calendar: calendar), .upcoming(days: 2))
        XCTAssertEqual(EventCountdown.state(on: date(2030, 10, 27, 0, 30), eventDate: date(2030, 10, 27, 23, 30), calendar: calendar), .today)
    }

    func testAcrossTheYearBoundary() {
        XCTAssertEqual(EventCountdown.state(on: date(2030, 12, 31, 23, 59), eventDate: date(2031, 1, 1, 0, 0), calendar: calendar), .upcoming(days: 1))
        XCTAssertEqual(EventCountdown.state(on: date(2030, 12, 1), eventDate: date(2031, 12, 1), calendar: calendar), .upcoming(days: 365))
    }

    // MARK: When the number changes

    func testRefreshDatesAreTheNextMidnights() {
        let dates = EventCountdown.refreshDates(after: date(2030, 6, 10, 10, 0), count: 3, calendar: calendar)
        XCTAssertEqual(dates, [date(2030, 6, 11, 0, 0), date(2030, 6, 12, 0, 0), date(2030, 6, 13, 0, 0)])
    }

    func testRefreshDatesStayOnMidnightAcrossADaylightSavingChange() {
        let dates = EventCountdown.refreshDates(after: date(2030, 3, 30, 10, 0), count: 3, calendar: calendar)
        XCTAssertEqual(dates, [date(2030, 3, 31, 0, 0), date(2030, 4, 1, 0, 0), date(2030, 4, 2, 0, 0)])
        let autumn = EventCountdown.refreshDates(after: date(2030, 10, 26, 10, 0), count: 2, calendar: calendar)
        XCTAssertEqual(autumn, [date(2030, 10, 27, 0, 0), date(2030, 10, 28, 0, 0)])
    }

    func testTheCountDropsByOneAtEachRefreshDate() {
        let now = date(2030, 6, 10, 21, 0)
        let event = date(2030, 6, 13)
        XCTAssertEqual(EventCountdown.state(on: now, eventDate: event, calendar: calendar), .upcoming(days: 3))
        let states = EventCountdown.refreshDates(after: now, count: 4, calendar: calendar)
            .map { EventCountdown.state(on: $0, eventDate: event, calendar: calendar) }
        XCTAssertEqual(states, [.upcoming(days: 2), .upcoming(days: 1), .today, .past(days: 1)])
    }

    func testNoRefreshDatesForACountOfZeroOrLess() {
        XCTAssertTrue(EventCountdown.refreshDates(after: date(2030, 6, 10), count: 0, calendar: calendar).isEmpty)
        XCTAssertTrue(EventCountdown.refreshDates(after: date(2030, 6, 10), count: -2, calendar: calendar).isEmpty)
    }

    // MARK: The name

    func testTheNameIsTrimmedCutAndNilWhenBlank() {
        XCTAssertNil(EventCountdown.cleanName(nil))
        XCTAssertNil(EventCountdown.cleanName(""))
        XCTAssertNil(EventCountdown.cleanName("  \n "))
        XCTAssertEqual(EventCountdown.cleanName("  Spring race \n"), "Spring race")
        let long = String(repeating: "a", count: 39) + " " + String(repeating: "b", count: 20)
        XCTAssertEqual(EventCountdown.cleanName(long), String(repeating: "a", count: 39), "cut to 40 characters, then trimmed again")
        XCTAssertEqual(EventCountdown.cleanName(String(repeating: "x", count: 60))?.count, EventCountdown.nameMaxLength)
    }
}
