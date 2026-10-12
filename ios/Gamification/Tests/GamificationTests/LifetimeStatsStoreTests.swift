import XCTest
@testable import Gamification
import FoodLogCore

final class LifetimeStatsStoreTests: XCTestCase {
    private func makeStore() -> LifetimeStatsStore {
        LifetimeStatsStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("gamification-lifetime-\(UUID().uuidString).json"))
    }

    private func event(_ foodId: String, day: Int, hour: Int = 12) -> UsageEvent {
        UsageEvent(foodId: foodId, servingId: "s1", numberOfUnits: 1, timestamp: TestClock.date(2026, 1, day, hour: hour))
    }

    private func goalStatus(day: Int, protein: Bool = false) -> DailyGoalStatus {
        DailyGoalStatus(date: String(format: "2026-01-%02d", day), metCalorieGoal: false, metProteinGoal: protein, metCarbGoal: false, metFatGoal: false)
    }

    func testRecordLogAccumulatesTotalsAndFirstLogDate() async throws {
        let store = makeStore()
        try await store.recordLog(nutritionDay: "2026-01-01", calories: 500, now: TestClock.date(2026, 1, 1))
        try await store.recordLog(nutritionDay: "2026-01-01", calories: 300, now: TestClock.date(2026, 1, 1, hour: 18))

        let snapshot = await store.current()
        XCTAssertEqual(snapshot.totalLogsEver, 2)
        XCTAssertEqual(snapshot.totalCaloriesEver, 800)
        XCTAssertEqual(snapshot.firstLogDate, TestClock.date(2026, 1, 1))
    }

    func testRecordedLifetimeStatsSurviveStoreRecreation() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("gamification-lifetime-\(UUID().uuidString).json")
        let firstStore = LifetimeStatsStore(fileURL: fileURL)
        try await firstStore.recordLog(
            nutritionDay: "2026-01-01",
            calories: 750,
            now: TestClock.date(2026, 1, 1)
        )
        try await firstStore.recordGoalStatus(goalStatus(day: 1, protein: true))

        let reloadedStore = LifetimeStatsStore(fileURL: fileURL)
        let snapshot = await reloadedStore.current()
        let proteinGoalDays = await reloadedStore.goalHitDays(.protein)

        XCTAssertEqual(snapshot.totalLogsEver, 1)
        XCTAssertEqual(snapshot.totalCaloriesEver, 750)
        XCTAssertEqual(snapshot.firstLogDate, TestClock.date(2026, 1, 1))
        XCTAssertEqual(proteinGoalDays, 1)
    }

    func testMaxSingleDayCaloriesTracksTheRunningDayTotalAcrossMultipleLogs() async throws {
        let store = makeStore()
        try await store.recordLog(nutritionDay: "2026-01-05", calories: 2000, now: TestClock.date(2026, 1, 5))
        try await store.recordLog(nutritionDay: "2026-01-05", calories: 3500, now: TestClock.date(2026, 1, 5, hour: 20))
        // A later log on a DIFFERENT (smaller) day must not lower the
        // already-recorded max.
        try await store.recordLog(nutritionDay: "2026-01-06", calories: 400, now: TestClock.date(2026, 1, 6))

        let snapshot = await store.current()
        XCTAssertEqual(snapshot.maxSingleDayCalories, 5500)
    }

    func testMaxSingleDayCaloriesHandlesABackdatedLogReturningToAnEarlierDay() async throws {
        let store = makeStore()
        try await store.recordLog(nutritionDay: "2026-01-05", calories: 1000, now: TestClock.date(2026, 1, 5))
        try await store.recordLog(nutritionDay: "2026-01-06", calories: 200, now: TestClock.date(2026, 1, 6))
        // Logged now, but backdated to the 5th -- should ADD to that day's
        // already-accumulated running total, not start a fresh one.
        try await store.recordLog(nutritionDay: "2026-01-05", calories: 4600, now: TestClock.date(2026, 1, 6, hour: 21))

        let snapshot = await store.current()
        XCTAssertEqual(snapshot.maxSingleDayCalories, 5600, "revisiting an earlier tracked day must accumulate onto its existing total, not reset it")
    }

    func testRecordGoalStatusCountsEachDayAtMostOncePerMacro() async throws {
        let store = makeStore()
        try await store.recordGoalStatus(goalStatus(day: 1, protein: true))
        try await store.recordGoalStatus(goalStatus(day: 1, protein: true)) // re-fetch of the same day
        try await store.recordGoalStatus(goalStatus(day: 2, protein: true))

        let count = await store.goalHitDays(.protein)
        XCTAssertEqual(count, 2, "re-recording the same day must not double-count")
    }

    /// harden-gamification-data-integrity 2.3, 3.2: the app re-fetches a
    /// selected older day, so A, B, then A again is a real order -- A must
    /// not count twice.
    func testAnOlderDayRefetchedAfterANewerOneIsNotCountedAgain() async throws {
        let store = makeStore()
        try await store.recordGoalStatus(goalStatus(day: 1, protein: true))
        try await store.recordGoalStatus(goalStatus(day: 2, protein: true))
        try await store.recordGoalStatus(goalStatus(day: 1, protein: true))

        let count = await store.goalHitDays(.protein)
        XCTAssertEqual(count, 2)
    }

    func testCountedGoalDaysSurviveAReload() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("gamification-lifetime-\(UUID().uuidString).json")
        let first = LifetimeStatsStore(fileURL: fileURL)
        try await first.recordGoalStatus(goalStatus(day: 1, protein: true))
        try await first.recordGoalStatus(goalStatus(day: 2, protein: true))

        let reloaded = LifetimeStatsStore(fileURL: fileURL)
        try await reloaded.recordGoalStatus(goalStatus(day: 1, protein: true))

        let count = await reloaded.goalHitDays(.protein)
        XCTAssertEqual(count, 2)
    }

    /// A ledger written before every counted day was kept knows only the
    /// last day per macro; that day must still not count again.
    func testALedgerFromBeforeTheDaySetStillGuardsItsLastCountedDay() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("gamification-lifetime-\(UUID().uuidString).json")
        let olderFile = #"{"totalLogsEver":3,"totalCaloriesEver":0,"maxSingleDayCalories":0,"goalHitDaysEver":{"protein":4},"lastCountedGoalDay":{"protein":"2026-01-02"},"recentDayCalories":{},"recentDayOrder":[]}"#
        try Data(olderFile.utf8).write(to: fileURL)
        let store = LifetimeStatsStore(fileURL: fileURL)

        try await store.recordGoalStatus(goalStatus(day: 2, protein: true))
        let unchanged = await store.goalHitDays(.protein)
        XCTAssertEqual(unchanged, 4)

        try await store.recordGoalStatus(goalStatus(day: 3, protein: true))
        let counted = await store.goalHitDays(.protein)
        XCTAssertEqual(counted, 5)
    }

    /// harden-gamification-data-integrity 2.2: a meal preset of N
    /// ingredients is N lifetime logs; its calories are the total.
    func testAPresetCountsOneLifetimeLogPerIngredient() async throws {
        let store = makeStore()
        try await store.recordLog(nutritionDay: "2026-01-01", calories: 600, now: TestClock.date(2026, 1, 1), entries: 3)

        let snapshot = await store.current()
        XCTAssertEqual(snapshot.totalLogsEver, 3)
        XCTAssertEqual(snapshot.totalCaloriesEver, 600)
    }

    /// harden-gamification-data-integrity 2.1: a backdated log's calories
    /// build up the day it was logged FOR, not the day of the tap.
    func testABackdatedLogAddsToTheSelectedDayNotTheTapDay() async throws {
        let store = makeStore()
        try await store.recordLog(nutritionDay: "2026-01-01", calories: 2000, now: TestClock.date(2026, 1, 1))
        try await store.recordLog(nutritionDay: "2026-01-02", calories: 1500, now: TestClock.date(2026, 1, 2))
        // On the 2nd, a forgotten dinner is added to the 1st.
        try await store.recordLog(nutritionDay: "2026-01-01", calories: 900, now: TestClock.date(2026, 1, 2, hour: 20))

        let snapshot = await store.current()
        XCTAssertEqual(snapshot.maxSingleDayCalories, 2900, "the 1st's total, not 1500 + 900 on the 2nd")
    }

    func testBackfillSeedsFromRetainedHistoryOnlyWhenTheLedgerIsEmpty() async throws {
        let store = makeStore()
        let events = [event("a", day: 1), event("b", day: 3)]
        let goals = [goalStatus(day: 1, protein: true), goalStatus(day: 3, protein: true)]

        try await store.backfillIfEmpty(events: events, goalStatuses: goals)
        var snapshot = await store.current()
        XCTAssertEqual(snapshot.totalLogsEver, 2)
        XCTAssertEqual(snapshot.firstLogDate, TestClock.date(2026, 1, 1))
        let proteinDays = await store.goalHitDays(.protein)
        XCTAssertEqual(proteinDays, 2)

        // A real log then arrives; a second backfill call must not
        // overwrite or double-count the now-nonempty ledger.
        try await store.recordLog(nutritionDay: "2026-01-10", calories: nil, now: TestClock.date(2026, 1, 10))
        try await store.backfillIfEmpty(events: events, goalStatuses: goals)
        snapshot = await store.current()
        XCTAssertEqual(snapshot.totalLogsEver, 3, "backfill must not re-run once the ledger has real data")
    }
}
