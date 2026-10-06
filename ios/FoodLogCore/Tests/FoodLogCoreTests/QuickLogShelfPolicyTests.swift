// QuickLogShelfPolicyTests.swift
//
// improve-food-day-flow (A3, spec food-day-flow "The quick-log shelves follow
// the day being shown"): the shelves show on a past day and today, on a
// future day only where one can be reached, and never when empty.

import XCTest
@testable import FoodLogCore

final class QuickLogShelfPolicyTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    // Spec: Catching up yesterday.
    func testAPastDayShowsAShelfThatHasSomethingInIt() {
        XCTAssertTrue(QuickLogShelfPolicy.showsShelf(on: .past, hasItems: true, allowsFutureDays: false))
        XCTAssertTrue(QuickLogShelfPolicy.showsShelf(on: .past, hasItems: true, allowsFutureDays: true))
    }

    func testTodayShowsAShelfThatHasSomethingInIt() {
        XCTAssertTrue(QuickLogShelfPolicy.showsShelf(on: .today, hasItems: true, allowsFutureDays: false))
        XCTAssertTrue(QuickLogShelfPolicy.showsShelf(on: .today, hasItems: true, allowsFutureDays: true))
    }

    // Spec: Tomorrow in the training experience / A future day in food-first.
    func testAFutureDayShowsAShelfOnlyWhereItCanBeReached() {
        XCTAssertTrue(QuickLogShelfPolicy.showsShelf(on: .future, hasItems: true, allowsFutureDays: true))
        XCTAssertFalse(QuickLogShelfPolicy.showsShelf(on: .future, hasItems: true, allowsFutureDays: false))
    }

    // Spec: Nothing to offer.
    func testAnEmptyShelfIsNeverShown() {
        for day in [QuickLogShelfPolicy.ShownDay.past, .today, .future] {
            XCTAssertFalse(QuickLogShelfPolicy.showsShelf(on: day, hasItems: false, allowsFutureDays: true), "\(day)")
            XCTAssertFalse(QuickLogShelfPolicy.showsShelf(on: day, hasItems: false, allowsFutureDays: false), "\(day)")
        }
    }

    func testTheShownDayIsReadInTheCalendarsOwnDays() {
        let now = date(2026, 10, 6, hour: 9)

        XCTAssertEqual(QuickLogShelfPolicy.shownDay(selected: date(2026, 10, 6, hour: 0), now: now, calendar: calendar), .today)
        XCTAssertEqual(QuickLogShelfPolicy.shownDay(selected: date(2026, 10, 6, hour: 23), now: now, calendar: calendar), .today, "later the same day is still today")
        XCTAssertEqual(QuickLogShelfPolicy.shownDay(selected: date(2026, 10, 5, hour: 23), now: now, calendar: calendar), .past)
        XCTAssertEqual(QuickLogShelfPolicy.shownDay(selected: date(2026, 9, 1), now: now, calendar: calendar), .past)
        XCTAssertEqual(QuickLogShelfPolicy.shownDay(selected: date(2026, 10, 7, hour: 0), now: now, calendar: calendar), .future)
    }
}
