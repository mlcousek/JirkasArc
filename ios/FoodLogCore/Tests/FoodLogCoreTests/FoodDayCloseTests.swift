// FoodDayCloseTests.swift
//
// improve-food-day-flow (A2, spec food-day-flow): closing a day's food log
// -- the per-day local store (close, undo, at least one entry, never a
// future day, survives a relaunch), "Edited after closing", and the
// complete-days streak with gaps and edited days. Real store on a unique
// temp file per test; synthetic days only.

import XCTest
@testable import FoodLogCore

final class FoodDayCloseTests: XCTestCase {
    private let today = "2026-10-06"
    private let closedAt = Date(timeIntervalSince1970: 1_791_000_000)

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func tempFile() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("food-day-closes-test-\(UUID().uuidString).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    // MARK: - Store

    // Spec: Closing today / Relaunch.
    func testClosingADayIsRecordedAndSurvivesARelaunch() async throws {
        let url = tempFile()
        let store = FoodDayCloseStore(fileURL: url)

        let record = try await store.close(day: today, today: today, entryCount: 3, now: closedAt)

        XCTAssertEqual(record, FoodDayClose(day: today, closedAt: closedAt, entryCount: 3))
        XCTAssertFalse(record.isEditedAfterClosing)

        let reopened = FoodDayCloseStore(fileURL: url)
        let stored = await reopened.record(for: today)
        XCTAssertEqual(stored, record)
        let days = await reopened.closedDays()
        XCTAssertEqual(days, [today])
    }

    // Spec: Nothing logged.
    func testADayWithoutAnEntryCannotBeClosed() async throws {
        let store = FoodDayCloseStore(fileURL: tempFile())

        do {
            try await store.close(day: today, today: today, entryCount: 0, now: closedAt)
            XCTFail("expected a throw")
        } catch let error as FoodDayCloseError {
            XCTAssertEqual(error, .nothingLogged)
        }
        let all = await store.all()
        XCTAssertTrue(all.isEmpty, "nothing was written")
    }

    func testAFutureOrMalformedDayCannotBeClosed() async throws {
        let store = FoodDayCloseStore(fileURL: tempFile())

        do {
            try await store.close(day: "2026-10-07", today: today, entryCount: 2, now: closedAt)
            XCTFail("expected a throw")
        } catch let error as FoodDayCloseError {
            XCTAssertEqual(error, .futureDay)
        }
        do {
            try await store.close(day: "tomorrow", today: today, entryCount: 2, now: closedAt)
            XCTFail("expected a throw")
        } catch let error as FoodDayCloseError {
            XCTAssertEqual(error, .invalidDay)
        }
        let all = await store.all()
        XCTAssertTrue(all.isEmpty)
    }

    func testAPastDayWithEntriesCanBeClosed() async throws {
        let store = FoodDayCloseStore(fileURL: tempFile())

        try await store.close(day: "2026-10-01", today: today, entryCount: 1, now: closedAt)

        let days = await store.closedDays()
        XCTAssertEqual(days, ["2026-10-01"])
    }

    // Spec: Undo.
    func testUndoRemovesTheRecordAndTheDayCanBeClosedAgain() async throws {
        let store = FoodDayCloseStore(fileURL: tempFile())
        try await store.close(day: today, today: today, entryCount: 3, now: closedAt)

        let undone = try await store.reopen(day: today)
        XCTAssertTrue(undone)
        let afterUndo = await store.record(for: today)
        XCTAssertNil(afterUndo)
        let undoneAgain = try await store.reopen(day: today)
        XCTAssertFalse(undoneAgain, "a day that is not closed has nothing to undo")

        try await store.close(day: today, today: today, entryCount: 4, now: closedAt.addingTimeInterval(600))
        let again = await store.record(for: today)
        XCTAssertEqual(again?.entryCount, 4)
    }

    // Spec: Adding to a closed day / An open day.
    func testAChangeMarksAClosedDayAsEditedAndRecordsNothingForAnOpenOne() async throws {
        let store = FoodDayCloseStore(fileURL: tempFile())
        try await store.close(day: today, today: today, entryCount: 3, now: closedAt)
        let firstEdit = closedAt.addingTimeInterval(3_600)

        let marked = try await store.markEdited(day: today, now: firstEdit)
        let openDay = try await store.markEdited(day: "2026-10-05", now: firstEdit)

        XCTAssertTrue(marked)
        XCTAssertFalse(openDay, "a day that is not closed records nothing")
        var record = await store.record(for: today)
        XCTAssertEqual(record?.editedAt, firstEdit)
        XCTAssertEqual(record?.isEditedAfterClosing, true)
        XCTAssertEqual(record?.closedAt, closedAt, "still closed, at the time it was closed")
        let all = await store.all()
        XCTAssertEqual(all.map(\.day), [today], "the open day got no record")

        // A second change keeps the first one's time and writes nothing new.
        let again = try await store.markEdited(day: today, now: firstEdit.addingTimeInterval(60))
        XCTAssertFalse(again)
        record = await store.record(for: today)
        XCTAssertEqual(record?.editedAt, firstEdit)
    }

    // Spec: Closing it again.
    func testClosingAgainAfterUndoClearsTheEditedMark() async throws {
        let store = FoodDayCloseStore(fileURL: tempFile())
        try await store.close(day: today, today: today, entryCount: 3, now: closedAt)
        try await store.markEdited(day: today, now: closedAt.addingTimeInterval(60))

        // Closing a day that is already closed changes nothing.
        let unchanged = try await store.close(day: today, today: today, entryCount: 9, now: closedAt.addingTimeInterval(120))
        XCTAssertTrue(unchanged.isEditedAfterClosing)
        XCTAssertEqual(unchanged.entryCount, 3)

        try await store.reopen(day: today)
        let fresh = try await store.close(day: today, today: today, entryCount: 4, now: closedAt.addingTimeInterval(180))
        XCTAssertFalse(fresh.isEditedAfterClosing)
        XCTAssertEqual(fresh.entryCount, 4)
    }

    func testAnOlderFileWithoutTheEditedMarkStillDecodes() async throws {
        let url = tempFile()
        let json = """
        [ { "closedAt": "2026-10-05T19:00:00Z", "day": "2026-10-05", "entryCount": 4 } ]
        """
        try Data(json.utf8).write(to: url)

        let store = FoodDayCloseStore(fileURL: url)
        let record = await store.record(for: "2026-10-05")

        XCTAssertEqual(record?.entryCount, 4)
        XCTAssertNil(record?.editedAt)
        XCTAssertEqual(record?.closedAt, ISO8601DateFormatter().date(from: "2026-10-05T19:00:00Z"))
    }

    // MARK: - Rules

    func testTheCardsStateForADay() {
        let closed = FoodDayClose(day: today, closedAt: closedAt, entryCount: 3)
        let edited = FoodDayClose(day: today, closedAt: closedAt, entryCount: 3, editedAt: closedAt.addingTimeInterval(60))

        XCTAssertEqual(FoodDayCloseRules.state(day: today, today: today, entryCount: 3, record: nil), .open)
        XCTAssertEqual(FoodDayCloseRules.state(day: "2026-10-01", today: today, entryCount: 1, record: nil), .open, "a past day with entries")
        XCTAssertEqual(FoodDayCloseRules.state(day: today, today: today, entryCount: 0, record: nil), .notOffered, "nothing logged")
        XCTAssertEqual(FoodDayCloseRules.state(day: "2026-10-07", today: today, entryCount: 2, record: nil), .notOffered, "a day after today")
        XCTAssertEqual(FoodDayCloseRules.state(day: today, today: today, entryCount: 3, record: closed), .closed(editedAfterClosing: false))
        XCTAssertEqual(FoodDayCloseRules.state(day: today, today: today, entryCount: 4, record: edited), .closed(editedAfterClosing: true))
        XCTAssertEqual(FoodDayCloseRules.state(day: today, today: today, entryCount: 0, record: closed), .closed(editedAfterClosing: false),
                       "a closed day stays closed even when its entries are gone")
        XCTAssertEqual(FoodDayCloseRules.state(day: "2026-10-05", today: today, entryCount: 2, record: closed), .open,
                       "another day's record says nothing about this one")
    }

    func testWhyADayCannotBeClosed() {
        XCTAssertNil(FoodDayCloseRules.refusal(day: today, today: today, entryCount: 1))
        XCTAssertEqual(FoodDayCloseRules.refusal(day: today, today: today, entryCount: 0), .nothingLogged)
        XCTAssertEqual(FoodDayCloseRules.refusal(day: "2026-10-07", today: today, entryCount: 5), .futureDay)
        XCTAssertEqual(FoodDayCloseRules.refusal(day: "06.10.2026", today: today, entryCount: 5), .invalidDay)
        XCTAssertTrue(FoodDayCloseRules.canClose(day: "2025-12-31", today: today, entryCount: 2))
    }

    // MARK: - Complete-days streak

    // Spec: Today not closed yet.
    func testTheStreakEndsYesterdayWhileTodayIsStillOpen() {
        let closed: Set<String> = ["2026-10-03", "2026-10-04", "2026-10-05"]
        XCTAssertEqual(CompleteDaysStreak.length(closedDays: closed, today: today, calendar: utc), 3)
    }

    func testClosingTodayExtendsTheStreak() {
        let closed: Set<String> = ["2026-10-03", "2026-10-04", "2026-10-05", "2026-10-06"]
        XCTAssertEqual(CompleteDaysStreak.length(closedDays: closed, today: today, calendar: utc), 4)
    }

    // Spec: A gap.
    func testADayThatIsNotClosedEndsTheStreak() {
        let closed: Set<String> = ["2026-10-06", "2026-10-05", "2026-10-03", "2026-10-02"]
        XCTAssertEqual(CompleteDaysStreak.length(closedDays: closed, today: today, calendar: utc), 2)
    }

    // Spec: Neither today nor yesterday.
    func testNoStreakWhenTheLastClosedDayIsTwoDaysAgo() {
        XCTAssertEqual(CompleteDaysStreak.length(closedDays: ["2026-10-04", "2026-10-03"], today: today, calendar: utc), 0)
        XCTAssertEqual(CompleteDaysStreak.length(closedDays: [], today: today, calendar: utc), 0)
    }

    func testTheStreakCrossesMonthAndYearBorders() {
        let closed: Set<String> = ["2026-12-30", "2026-12-31", "2027-01-01", "2027-01-02"]
        XCTAssertEqual(CompleteDaysStreak.length(closedDays: closed, today: "2027-01-02", calendar: utc), 4)
        XCTAssertEqual(CompleteDaysStreak.length(closedDays: ["2026-02-28", "2026-03-01"], today: "2026-03-01", calendar: utc), 2)
    }

    func testAMalformedTodayHasNoStreak() {
        XCTAssertEqual(CompleteDaysStreak.length(closedDays: ["2026-10-05"], today: "today", calendar: utc), 0)
    }

    // Spec: An edited day.
    func testAnEditedDayStillCountsTowardTheStreak() async throws {
        let store = FoodDayCloseStore(fileURL: tempFile())
        try await store.close(day: "2026-10-05", today: today, entryCount: 3, now: closedAt)
        try await store.close(day: today, today: today, entryCount: 2, now: closedAt.addingTimeInterval(86_400))
        try await store.markEdited(day: "2026-10-05", now: closedAt.addingTimeInterval(90_000))

        let days = await store.closedDays()

        XCTAssertEqual(CompleteDaysStreak.length(closedDays: days, today: today, calendar: utc), 2)
    }
}
