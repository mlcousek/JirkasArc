// LoveMinuteTests.swift
//
// add-partner-love-theme D6, spec love-messages: the love message's minute
// is in 08:00-12:59 every day of the week, the same every time it is
// computed, kept away from other reminders, and at the same wall-clock
// minute across a DST change. Also LoveDay's day-key arithmetic.

import XCTest
@testable import FoodLogCore

final class LoveMinuteTests: XCTestCase {
    func testAThousandDaysStayInTheWindowAndVary() {
        var minutes = Set<Int>()
        var weekendSeen = false
        var day = "2030-01-01"
        for offset in 0..<1_000 {
            let minute = LoveMinute.baseMinute(seed: "sample-seed-0001", day: day)
            XCTAssertGreaterThanOrEqual(minute, 8 * 60, day)
            XCTAssertLessThan(minute, 13 * 60, day)
            minutes.insert(minute)
            // 2030-01-05 is a Saturday: weekends are planned like any day.
            if offset % 7 == 4 { weekendSeen = true }
            day = LoveDay.adding(1, to: day)!
        }
        XCTAssertTrue(weekendSeen)
        XCTAssertGreaterThan(minutes.count, 100, "the minutes should spread over the window")
    }

    func testTheMinuteIsStable() {
        let first = LoveMinute.minute(seed: "sample-seed-0001", day: "2030-03-14", otherReminderMinutes: [510])
        for _ in 0..<3 {
            XCTAssertEqual(LoveMinute.minute(seed: "sample-seed-0001", day: "2030-03-14", otherReminderMinutes: [510]), first)
        }
        XCTAssertNotEqual(
            LoveMinute.baseMinute(seed: "sample-seed-0001", day: "2030-03-14"),
            LoveMinute.baseMinute(seed: "another-seed", day: "2030-03-14"),
            "a different pack seed gives a different minute (for this fixed pair)"
        )
    }

    func testAClashMovesToTheNextFreeMinute() {
        // Breakfast at 08:30, the day's minute 08:34: within 10 minutes.
        XCTAssertEqual(LoveMinute.resolve(base: 8 * 60 + 34, otherReminderMinutes: [8 * 60 + 30]), 8 * 60 + 41)
        // Exactly 10 minutes away is still a clash; 11 is free.
        XCTAssertEqual(LoveMinute.resolve(base: 8 * 60 + 40, otherReminderMinutes: [8 * 60 + 30]), 8 * 60 + 41)
        XCTAssertEqual(LoveMinute.resolve(base: 8 * 60 + 41, otherReminderMinutes: [8 * 60 + 30]), 8 * 60 + 41)
        // Two reminders in a row push it past both.
        XCTAssertEqual(LoveMinute.resolve(base: 9 * 60, otherReminderMinutes: [9 * 60, 9 * 60 + 15]), 9 * 60 + 26)
    }

    func testAClashAtTheEndOfTheWindowMovesBackInsteadOfPast13() {
        let minute = LoveMinute.resolve(base: 12 * 60 + 55, otherReminderMinutes: [12 * 60 + 50])
        XCTAssertLessThan(minute, 13 * 60)
        XCTAssertGreaterThanOrEqual(minute, 8 * 60)
        XCTAssertGreaterThan(abs(minute - (12 * 60 + 50)), LoveMinute.clashGap)
        XCTAssertEqual(minute, 12 * 60 + 39)
    }

    func testDSTDaysKeepTheWallClockMinute() {
        let calendar = LoveTestSupport.prague
        for day in ["2030-03-31", "2030-10-27"] {
            let date = LoveDay.date(day: day, minute: 10 * 60 + 12, calendar: calendar)!
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            XCTAssertEqual(LoveDay.key(of: date, calendar: calendar), day)
            XCTAssertEqual(parts.hour, 10, day)
            XCTAssertEqual(parts.minute, 12, day)
        }
        XCTAssertEqual(
            LoveDay.triggerComponents(day: "2030-03-31", minute: 8 * 60 + 5),
            DateComponents(year: 2030, month: 3, day: 31, hour: 8, minute: 5)
        )
    }

    func testDayKeys() {
        XCTAssertTrue(LoveDay.isValid("2030-02-28"))
        XCTAssertFalse(LoveDay.isValid("2030-02-29"))
        XCTAssertTrue(LoveDay.isValid("2032-02-29"))
        XCTAssertFalse(LoveDay.isValid("2030-3-14"))
        XCTAssertFalse(LoveDay.isValid("2030-03-14T10:00"))
        XCTAssertFalse(LoveDay.isValid("２０３０-03-14"))
        XCTAssertEqual(LoveDay.adding(1, to: "2030-12-31"), "2031-01-01")
        XCTAssertEqual(LoveDay.adding(-1, to: "2030-03-01"), "2030-02-28")
        XCTAssertEqual(LoveDay.days(from: "2030-01-01", to: "2030-03-14"), 72)
        XCTAssertEqual(LoveDay.days(from: "2030-03-14", to: "2030-03-13"), -1)
    }
}
