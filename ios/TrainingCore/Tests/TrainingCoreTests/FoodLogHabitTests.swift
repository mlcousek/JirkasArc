// FoodLogHabitTests.swift
//
// improve-food-day-flow (A2, spec food-day-flow): closing a day's food log
// ticks the plan's `food-log` habit -- only when the ladder has it, the plan
// expects it that day, the day is inside the vault's back-fill window and
// the app may record -- and the evening reminder mentions a food log that is
// not closed.
//
// Synthetic inline projections (HabitFixtures: the 2030 season, "today"
// Wednesday 2030-10-23), with a sixth habit, `food-log`, added to the
// ladder and to the days' expected habits. Nothing here is the mirrored
// vault contract, and nothing is real data.

import XCTest
@testable import TrainingCore

final class FoodLogHabitTests: XCTestCase {
    private let today = HabitFixtures.today
    private let prague = TimeZone(identifier: "Europe/Prague")!
    /// 2030-10-23 00:00 in Prague.
    private let midnight = Date(timeIntervalSince1970: 1_918_936_800)

    // MARK: - Fixtures

    /// The five-step ladder plus an active `food-log` habit (every day).
    private func ladder(source: String? = nil) -> [[String: Any]] {
        var extra: [String: Any] = [:]
        if let source { extra["source"] = source }
        let everyDay: [String: Any] = ["kind": "daily"]
        let label: [String: String] = ["en": "Close the food log", "cz": "Uzavřít deník jídla"]
        let foodLog = HabitFixtures.habit(FoodLogHabit.habitID, step: 5, label: label, state: "active", schedule: everyDay, extra: extra)
        return HabitFixtures.ladder() + [foodLog]
    }

    /// The projection with `food-log` expected on the days `isExpected`
    /// says, and counted `doneOn` times on the recorded days listed there.
    private func data(
        ladder: [[String: Any]]? = nil,
        isExpected: @escaping (LocalDate) -> Bool = { _ in true },
        doneOn: [String: Int] = [:]
    ) throws -> Data {
        try HabitFixtures.data(ladder: ladder ?? self.ladder()) { date, day in
            guard isExpected(date) else { return }
            var expected = day["habitsExpected"] as? [String] ?? []
            expected.append(FoodLogHabit.habitID)
            day["habitsExpected"] = expected
            if var counts = day["habitsDone"] as? [String: Int] {
                counts[FoodLogHabit.habitID] = doneOn[date.description] ?? 0
                day["habitsDone"] = counts
            }
        }
    }

    private func tick(closed: Bool, on date: LocalDate, _ snapshot: TrainingSnapshot?) -> HabitTickPayload? {
        FoodLogHabit.tick(closed: closed, on: date, snapshot: snapshot, today: today)
    }

    // MARK: - The tick

    // Spec: Expected today.
    func testClosingADayThePlanExpectsTheHabitOnTicksIt() throws {
        let snapshot = try HabitFixtures.snapshot(try data())

        let payload = tick(closed: true, on: today, snapshot)

        XCTAssertEqual(payload, HabitTickPayload(date: today, habitId: "food-log", done: true))
    }

    // Spec: Undo.
    func testUndoingTheCloseTakesTheTickBack() throws {
        let ticked = try HabitFixtures.snapshot(try data(), ticks: [
            HabitFixtures.tick("food-log", "2030-10-23", done: true, seq: 1)
        ])

        XCTAssertEqual(tick(closed: false, on: today, ticked), HabitTickPayload(date: today, habitId: "food-log", done: false))
        XCTAssertNil(tick(closed: true, on: today, ticked), "already ticked: closing again records nothing")
    }

    func testReopeningADayThatWasNeverTickedRecordsNothing() throws {
        let snapshot = try HabitFixtures.snapshot(try data())

        XCTAssertNil(tick(closed: false, on: today, snapshot))
    }

    func testADayTheVaultAlreadyCountedAsDoneIsNotTickedAgain() throws {
        let yesterday = D.date("2030-10-22")
        let snapshot = try HabitFixtures.snapshot(try data(doneOn: ["2030-10-22": 1]))

        XCTAssertNil(tick(closed: true, on: yesterday, snapshot), "the vault's count already says done")
        XCTAssertEqual(tick(closed: false, on: yesterday, snapshot), HabitTickPayload(date: yesterday, habitId: "food-log", done: false))
    }

    // Spec: No such habit.
    func testALadderWithoutTheHabitRecordsNothing() throws {
        // The fixture's own five-step ladder, even with days that list the id.
        let snapshot = try HabitFixtures.snapshot(try data(ladder: HabitFixtures.ladder()))

        XCTAssertNil(tick(closed: true, on: today, snapshot))
        XCTAssertNil(tick(closed: false, on: today, snapshot))
    }

    // Spec: Not expected that day.
    func testADayThePlanDoesNotExpectTheHabitOnRecordsNothing() throws {
        let monday = D.date("2030-10-21")
        let snapshot = try HabitFixtures.snapshot(try data(isExpected: { $0 == monday }))

        XCTAssertNil(tick(closed: true, on: today, snapshot))
        XCTAssertEqual(tick(closed: true, on: monday, snapshot), HabitTickPayload(date: monday, habitId: "food-log", done: true))
    }

    // Spec: The connection cannot record.
    func testNothingIsRecordedWhenTheAppMayNotRecord() throws {
        let readOnly = try HabitFixtures.snapshot(try data(), canRecord: false)

        XCTAssertNil(tick(closed: true, on: today, readOnly))
        XCTAssertNil(tick(closed: true, on: today, nil), "no plan loaded at all (food-first)")
    }

    // Spec: Too far back.
    func testOnlyTodayAndTheFourteenDaysBeforeAreTicked() throws {
        let snapshot = try HabitFixtures.snapshot(try data())

        XCTAssertNotNil(tick(closed: true, on: D.date("2030-10-09"), snapshot), "14 days back is still accepted")
        XCTAssertNil(tick(closed: true, on: D.date("2030-10-08"), snapshot), "15 days back is refused by the vault")
        XCTAssertNil(tick(closed: true, on: D.date("2030-10-24"), snapshot), "a day after today")
    }

    func testAHabitTheVaultMeasuresItselfTakesNoTick() throws {
        let measured = try HabitFixtures.snapshot(try data(ladder: ladder(source: "activity")))
        let fromNotes = try HabitFixtures.snapshot(try data(ladder: ladder(source: "daily-note")))

        XCTAssertNil(tick(closed: true, on: today, measured))
        XCTAssertNotNil(tick(closed: true, on: today, fromNotes))
    }

    // MARK: - The evening reminder

    private func eveningBodies(_ snapshot: TrainingSnapshot, language: TrainingLanguage = .english, days: Int = 1, closed: Set<LocalDate>?) -> [String] {
        TrainingReminderPlanner
            .plan(snapshot: snapshot, today: today, now: midnight, timeZone: prague, language: language, days: days, closedFoodDays: closed)
            .filter { $0.kind == .eveningHabits }
            .map(\.body)
    }

    // Spec: Open habits, open food log / Food log already closed.
    func testTheEveningReminderMentionsAFoodLogThatIsNotClosed() throws {
        let snapshot = try HabitFixtures.snapshot(try data())

        XCTAssertEqual(eveningBodies(snapshot, closed: []), ["Tick today's habits and close your food log."])
        XCTAssertEqual(eveningBodies(snapshot, closed: [today]), ["Tick today's habits before bed."])
        XCTAssertEqual(eveningBodies(snapshot, language: .czech, closed: []), ["Odškrtni si dnešní návyky a uzavři deník jídla."])
        XCTAssertEqual(eveningBodies(snapshot, language: .czech, closed: [today]), ["Před spaním si odškrtni dnešní návyky."])
    }

    func testWithoutTheClosedDaysTheReminderReadsAsBefore() throws {
        let snapshot = try HabitFixtures.snapshot(try data())

        XCTAssertEqual(eveningBodies(snapshot, closed: nil), ["Tick today's habits before bed."])
    }

    func testEachDayOfTheWindowIsAskedOnItsOwn() throws {
        let snapshot = try HabitFixtures.snapshot(try data())

        // Today is closed, tomorrow is not.
        XCTAssertEqual(eveningBodies(snapshot, days: 2, closed: [today]), [
            "Tick today's habits before bed.",
            "Tick today's habits and close your food log."
        ])
    }

    // Spec: Nothing to tick.
    func testNoEveningReminderWhenEveryHabitIsTicked() throws {
        // A plain ladder; every habit expected today is ticked on the phone.
        let allTicked = try HabitFixtures.snapshot(ticks: [
            HabitFixtures.tick("holds", "2030-10-23", done: true, seq: 1),
            HabitFixtures.tick("walk", "2030-10-23", done: true, seq: 2)
        ])

        XCTAssertEqual(eveningBodies(allTicked, closed: []), [], "an open food log alone plans no reminder")
    }
}
