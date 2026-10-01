// HabitTimelineTests.swift
//
// The habit engine (add-interactive-habits design D2-D5; spec
// training-habits), on synthetic inline fixtures only (HabitFixtures):
//
//   - tolerant decoding of the vault's `streak` / `history` / `adherence`
//     and `habits.backfillDays`, in the shapes that are not settled yet;
//   - a day's state from the history, the plan's day and the phone's tick;
//   - the streak rules: expected and done extends, expected and missed
//     ends, not expected neither, today not done yet neither;
//   - the fallback without the vault's fields, limited to the days known;
//   - the vault's numbers moved by exactly what the phone's ticks change;
//   - multi-dose days: the phone's dose count and what a counter step
//     records (on/off only on the wire, decision A42);
//   - the back-fill window.

import XCTest
@testable import TrainingCore

final class HabitTimelineTests: XCTestCase {
    private let today = HabitFixtures.today

    private func timeline(_ id: String, _ snapshot: TrainingSnapshot, doses: HabitDoseLedger = .empty) throws -> HabitTimeline {
        let habit = try XCTUnwrap(snapshot.habits.habit(id))
        return HabitTimeline(habit: habit, snapshot: snapshot, today: today, doses: doses)
    }

    private func state(_ timeline: HabitTimeline, _ date: String) -> HabitDayState? {
        timeline.record(on: D.date(date))?.state
    }

    // MARK: Decoding

    func testTheVaultsFieldsAreAbsentUntilItPublishesThem() throws {
        let projection = try HabitFixtures.projection(try HabitFixtures.data())
        let walk = try XCTUnwrap(projection.habits.habit("walk"))
        XCTAssertNil(walk.streak)
        XCTAssertNil(walk.history)
        XCTAssertNil(walk.adherence)
        XCTAssertNil(projection.habits.backfillDays)
    }

    func testStreakHistoryAndAdherenceDecodeTolerantly() throws {
        let extra: [String: Any] = [
            "streak": ["current": 4.0, "best": "many", "unit": "fortnight", "lastDone": "soon"],
            "history": [
                ["date": "2030-10-20", "expected": true, "done": true],
                ["date": "2030-10-21", "expected": true, "done": false],
                ["date": "2030-10-22", "expected": false, "done": NSNull()],
                ["date": "not a date", "expected": 1, "done": 1],
                ["date": "2030-10-19", "expected": 2, "done": 1.0],
                ["date": "2030-10-18"]
            ],
            "adherence": ["d7": 86, "d14": ["done": 11, "expected": 14, "pct": 79], "d30": "high", "d84": 140]
        ]
        let data = try HabitFixtures.data(ladder: HabitFixtures.ladder(holdsExtra: extra), backfillDays: 7)
        let projection = try HabitFixtures.projection(data)
        let holds = try XCTUnwrap(projection.habits.habit("holds"))

        let streak = try XCTUnwrap(holds.streak)
        XCTAssertEqual(streak.current, 4)
        XCTAssertNil(streak.best)
        XCTAssertEqual(streak.unit, .unknown("fortnight"))
        XCTAssertNil(streak.lastDone)

        // The entry without a date is dropped; the rest are sorted.
        let history = try XCTUnwrap(holds.history)
        XCTAssertEqual(history.map(\.date.description), ["2030-10-18", "2030-10-19", "2030-10-20", "2030-10-21", "2030-10-22"])
        XCTAssertNil(history[0].expected)
        XCTAssertEqual(history[1].expected, .count(2))
        XCTAssertEqual(history[1].done, .count(1))
        XCTAssertEqual(history[2].expected, .flag(true))
        XCTAssertEqual(history[2].done, .flag(true))
        XCTAssertEqual(history[3].done, .flag(false))
        XCTAssertEqual(history[4].expected, .flag(false))
        XCTAssertNil(history[4].done)

        XCTAssertEqual(holds.adherence, HabitAdherence(d7: 86, d14: 79, d30: nil, d84: 100))
        XCTAssertEqual(projection.habits.backfillDays, 7)
        XCTAssertEqual(HabitBackfill.windowDays(projection.habits), 7)

        // A flag reads against the habit's two doses a day.
        let line = try timeline("holds", TrainingSnapshot(projection: projection))
        XCTAssertEqual(state(line, "2030-10-19"), .partly)
        XCTAssertEqual(state(line, "2030-10-20"), .done)
        XCTAssertEqual(line.record(on: D.date("2030-10-20"))?.done, 2)
        XCTAssertEqual(state(line, "2030-10-21"), .missed)
        XCTAssertEqual(state(line, "2030-10-22"), .notExpected)
        // No `expected` in the history: the plan's own day answers.
        XCTAssertEqual(state(line, "2030-10-18"), .partly)
    }

    func testAMalformedBackfillWindowFallsBackToTheDefault() throws {
        for value in [-3, "a week"] as [Any] {
            let projection = try HabitFixtures.projection(try HabitFixtures.data(backfillDays: value))
            XCTAssertNil(projection.habits.backfillDays)
            XCTAssertEqual(HabitBackfill.windowDays(projection.habits), 14)
        }
    }

    // MARK: Days

    func testADaysStateFromThePlan() throws {
        let snapshot = try HabitFixtures.snapshot()
        let walk = try timeline("walk", snapshot)
        XCTAssertEqual(walk.records.count, 84)
        XCTAssertEqual(walk.records.last?.date, today)
        XCTAssertEqual(state(walk, "2030-10-16"), .missed)
        XCTAssertEqual(state(walk, "2030-10-22"), .done)
        // Today is expected and not done yet: open, not missed.
        XCTAssertEqual(state(walk, "2030-10-23"), .open)
        // Before the plan's window nothing is known.
        XCTAssertEqual(state(walk, "2030-10-06"), .unknown)
        XCTAssertEqual(walk.knownDays, 17)
        XCTAssertFalse(walk.hasVaultHistory)

        let gym = try timeline("gym", snapshot)
        XCTAssertEqual(state(gym, "2030-10-21"), .done)
        XCTAssertEqual(state(gym, "2030-10-22"), .notExpected)
        XCTAssertEqual(state(gym, "2030-10-10"), .missed)

        let holds = try timeline("holds", snapshot)
        XCTAssertEqual(state(holds, "2030-10-11"), .partly)
        // An uncapped count of four is simply done.
        XCTAssertEqual(state(holds, "2030-10-13"), .done)
        XCTAssertEqual(state(holds, "2030-10-16"), .missed)
    }

    func testAnExpectedDayWithoutCountsIsUnknownNotMissed() throws {
        let data = try HabitFixtures.data { date, day in
            if date == D.date("2030-10-20") { day["habitsDone"] = NSNull() }
        }
        let walk = try timeline("walk", try HabitFixtures.snapshot(data))
        XCTAssertEqual(state(walk, "2030-10-20"), .unknown)
        // The count stops there, and says the streak may be longer.
        XCTAssertEqual(walk.streak.current, 2)
        XCTAssertTrue(walk.streak.isAtLeast)
    }

    // MARK: Streak rules (fallback)

    func testExpectedAndDoneExtendsAndMissedEnds() throws {
        let walk = try timeline("walk", try HabitFixtures.snapshot())
        // 17 ... 22 October; the 16th was missed; today doesn't break it.
        XCTAssertEqual(walk.streak.current, 6)
        XCTAssertEqual(walk.streak.best, 7)
        XCTAssertEqual(walk.streak.unit, .day)
        XCTAssertEqual(walk.streak.source, .phoneEstimate)
        XCTAssertFalse(walk.streak.isAtLeast)
        XCTAssertEqual(walk.streak.lastDone, D.date("2030-10-22"))
    }

    func testNotExpectedDaysNeitherExtendNorBreak() throws {
        let gym = try timeline("gym", try HabitFixtures.snapshot())
        // The 14th, 17th and 21st, with not-expected days in between.
        XCTAssertEqual(gym.streak.current, 3)
        XCTAssertEqual(gym.streak.unit, .occurrence)
        XCTAssertFalse(gym.streak.isAtLeast)
    }

    func testARunThatReachesTheEdgeOfWhatThePhoneKnowsIsAtLeast() throws {
        let data = try HabitFixtures.data { date, day in
            guard date == D.date("2030-10-10"), var done = day["habitsDone"] as? [String: Any] else { return }
            done["gym"] = 1
            day["habitsDone"] = done
        }
        let gym = try timeline("gym", try HabitFixtures.snapshot(data))
        XCTAssertEqual(gym.streak.current, 5)
        XCTAssertTrue(gym.streak.isAtLeast)
    }

    func testATickTodayExtendsTheStreakImmediately() throws {
        let snapshot = try HabitFixtures.snapshot(ticks: [HabitFixtures.tick("walk", "2030-10-23", done: true, seq: 1)])
        let walk = try timeline("walk", snapshot)
        XCTAssertEqual(state(walk, "2030-10-23"), .done)
        XCTAssertEqual(walk.streak.current, 7)
        XCTAssertEqual(walk.streak.lastDone, today)
    }

    func testBackFillingAMissedDayJoinsTheRunsAndUntickingBreaksOne() throws {
        let filled = try HabitFixtures.snapshot(ticks: [HabitFixtures.tick("walk", "2030-10-16", done: true, seq: 1)])
        // 9 ... 22 October.
        XCTAssertEqual(try timeline("walk", filled).streak.current, 14)
        XCTAssertEqual(try timeline("walk", filled).streak.best, 14)

        let unticked = try HabitFixtures.snapshot(ticks: [
            HabitFixtures.tick("walk", "2030-10-16", done: true, seq: 1),
            HabitFixtures.tick("walk", "2030-10-16", done: false, seq: 2),
            HabitFixtures.tick("walk", "2030-10-21", done: false, seq: 3)
        ])
        let walk = try timeline("walk", unticked)
        XCTAssertEqual(state(walk, "2030-10-16"), .missed)
        XCTAssertEqual(state(walk, "2030-10-21"), .missed)
        XCTAssertEqual(walk.streak.current, 1)
    }

    func testADoneTickOutsideThePlansWindowStillCounts() throws {
        let snapshot = try HabitFixtures.snapshot(ticks: [HabitFixtures.tick("walk", "2030-10-06", done: true, seq: 1)])
        XCTAssertEqual(state(try timeline("walk", snapshot), "2030-10-06"), .done)
    }

    // MARK: The vault's numbers and the phone's ticks

    private func published(missed: Set<String> = [], unit: String = "day") throws -> Data {
        try HabitFixtures.data(ladder: HabitFixtures.ladder(walkExtra: [
            "streak": ["current": 120, "best": 130, "unit": unit, "lastDone": "2030-10-22"],
            "history": HabitFixtures.history(missed: missed),
            "adherence": ["d7": 100, "d14": 100, "d30": 100, "d84": 100]
        ]))
    }

    func testTheVaultsStreakIsShownUntouchedWithoutTicks() throws {
        let walk = try timeline("walk", try HabitFixtures.snapshot(try published()))
        XCTAssertTrue(walk.hasVaultHistory)
        XCTAssertEqual(walk.knownDays, 84)
        XCTAssertEqual(walk.streak.current, 120)
        XCTAssertEqual(walk.streak.best, 130)
        XCTAssertEqual(walk.streak.source, .vault)
        XCTAssertFalse(walk.streak.isAtLeast)
        XCTAssertEqual(walk.adherence.map(\.pct), [100, 100, 100, 100])
        XCTAssertTrue(walk.adherence.allSatisfy { !$0.isEstimate })
    }

    func testATickTodayMovesTheVaultsStreakByOne() throws {
        let snapshot = try HabitFixtures.snapshot(try published(), ticks: [HabitFixtures.tick("walk", "2030-10-23", done: true, seq: 1)])
        let walk = try timeline("walk", snapshot)
        XCTAssertEqual(walk.streak.current, 121)
        XCTAssertEqual(walk.streak.best, 130)
        XCTAssertEqual(walk.streak.source, .vaultWithPhoneTicks)
        XCTAssertEqual(walk.streak.lastDone, today)
    }

    func testANewBestFollowsTheCurrentStreak() throws {
        let data = try HabitFixtures.data(ladder: HabitFixtures.ladder(walkExtra: [
            "streak": ["current": 120, "best": 120, "unit": "day"],
            "history": HabitFixtures.history()
        ]))
        let snapshot = try HabitFixtures.snapshot(data, ticks: [HabitFixtures.tick("walk", "2030-10-23", done: true, seq: 1)])
        XCTAssertEqual(try timeline("walk", snapshot).streak.best, 121)
    }

    func testUntickingAPastDayBreaksTheVaultsStreak() throws {
        let snapshot = try HabitFixtures.snapshot(try published(), ticks: [HabitFixtures.tick("walk", "2030-10-20", done: false, seq: 1)])
        let walk = try timeline("walk", snapshot)
        // Only the 21st and 22nd are left.
        XCTAssertEqual(walk.streak.current, 2)
        XCTAssertEqual(walk.streak.best, 130)
        XCTAssertFalse(walk.streak.isAtLeast)
        // Each window is recounted, because a day inside it changed.
        XCTAssertEqual(walk.adherence.map(\.pct), [83, 92, 96, 98])
        XCTAssertTrue(walk.adherence.allSatisfy(\.isEstimate))
    }

    func testAStreakTheVaultBrokeIsMovedByTheSameDifference() throws {
        // The vault's history has a miss on the 12th and its streak says 10.
        let data = try HabitFixtures.data(ladder: HabitFixtures.ladder(walkExtra: [
            "streak": ["current": 10, "best": 40, "unit": "occurrence"],
            "history": HabitFixtures.history(missed: ["2030-10-12"])
        ]))
        let untouched = try timeline("walk", try HabitFixtures.snapshot(data))
        XCTAssertEqual(untouched.streak.current, 10)
        XCTAssertEqual(untouched.streak.unit, .occurrence)
        let ticked = try timeline("walk", try HabitFixtures.snapshot(data, ticks: [HabitFixtures.tick("walk", "2030-10-23", done: true, seq: 1)]))
        XCTAssertEqual(ticked.streak.current, 11)
    }

    func testAWeekStreakIsNeverRecountedOnThePhone() throws {
        let snapshot = try HabitFixtures.snapshot(try published(unit: "week"), ticks: [HabitFixtures.tick("walk", "2030-10-23", done: true, seq: 1)])
        let walk = try timeline("walk", snapshot)
        XCTAssertEqual(walk.streak.current, 120)
        XCTAssertEqual(walk.streak.unit, .week)
        XCTAssertEqual(walk.streak.source, .vault)
        // The day itself still shows the tick.
        XCTAssertEqual(state(walk, "2030-10-23"), .done)
    }

    // MARK: Adherence

    func testFallbackAdherenceCoversOnlyTheWindowsThePhoneKnows() throws {
        let walk = try timeline("walk", try HabitFixtures.snapshot())
        // 17 known days: 7 and 14 are counted, 30 and 84 are not.
        XCTAssertEqual(walk.adherence.map(\.days), [7, 14, 30, 84])
        XCTAssertEqual(walk.adherence.map(\.pct), [100, 92, nil, nil])
        XCTAssertTrue(walk.adherence.allSatisfy(\.isEstimate))
    }

    func testTodayNotDoneYetDoesNotCountAgainstAdherence() throws {
        let walk = try timeline("walk", try HabitFixtures.snapshot())
        XCTAssertEqual(HabitTimeline.tally(walk.records, window: 7, today: today), HabitTally(done: 6, expected: 6))
        let ticked = try timeline("walk", try HabitFixtures.snapshot(ticks: [HabitFixtures.tick("walk", "2030-10-23", done: true, seq: 1)]))
        XCTAssertEqual(HabitTimeline.tally(ticked.records, window: 7, today: today), HabitTally(done: 7, expected: 7))
        XCTAssertNil(HabitTimeline.tally(walk.records, window: 1, today: today))
    }

    func testTheGatesWindowIsThe14DayNumberWhenTheVaultPublishesIt() throws {
        let data = try HabitFixtures.data(ladder: HabitFixtures.ladder(walkExtra: [
            "window14": ["done": 11, "expected": 14, "pct": 78, "recordedDays": 14]
        ]))
        let walk = try timeline("walk", try HabitFixtures.snapshot(data))
        XCTAssertEqual(walk.adherence[1], HabitAdherenceValue(days: 14, pct: 78, isEstimate: false))
        // A tick inside the window recounts it.
        let ticked = try timeline("walk", try HabitFixtures.snapshot(data, ticks: [HabitFixtures.tick("walk", "2030-10-23", done: true, seq: 1)]))
        XCTAssertEqual(ticked.adherence[1], HabitAdherenceValue(days: 14, pct: 92, isEstimate: true))
    }

    // MARK: Multi-dose days

    func testDosesOnTheDayFromTheVaultThePhonesCountAndItsTick() throws {
        let partlyToday = try HabitFixtures.data { date, day in
            if date == D.date("2030-10-23") { day["habitsDone"] = ["holds": 1] }
        }
        let fromVault = try timeline("holds", try HabitFixtures.snapshot(partlyToday))
        XCTAssertEqual(state(fromVault, "2030-10-23"), .partly)
        // Today's missing dose doesn't break the run of the 22nd.
        XCTAssertEqual(fromVault.streak.current, 1)

        var doses = HabitDoseLedger()
        doses.set(1, on: today, habitID: "holds")
        let counted = try timeline("holds", try HabitFixtures.snapshot(), doses: doses)
        XCTAssertEqual(counted.record(on: today)?.done, 1)
        XCTAssertEqual(state(counted, "2030-10-23"), .partly)

        let done = try timeline("holds", try HabitFixtures.snapshot(ticks: [HabitFixtures.tick("holds", "2030-10-23", done: true, seq: 1)]))
        XCTAssertEqual(done.record(on: today)?.done, 2)
        XCTAssertEqual(done.streak.current, 2)

        // Off on the phone: its own count is what is left.
        let off = try timeline("holds", try HabitFixtures.snapshot(partlyToday, ticks: [HabitFixtures.tick("holds", "2030-10-23", done: false, seq: 1)]))
        XCTAssertEqual(state(off, "2030-10-23"), .open)
        XCTAssertEqual(off.record(on: today)?.vaultDone, 1)
    }

    func testAPastDayWithSomeDosesEndsTheRun() throws {
        let holds = try timeline("holds", try HabitFixtures.snapshot())
        // The 22nd; the 21st was missed. Best: 7 ... 10 October.
        XCTAssertEqual(holds.streak.current, 1)
        XCTAssertEqual(holds.streak.best, 4)
    }

    func testACounterStepRecordsOnlyOnOrOff() throws {
        func record(expected: Int = 2, done: Int, vault: Int? = nil, local: Bool? = nil) -> HabitDayRecord {
            let state: HabitDayState = done >= expected ? .done : (done > 0 ? .partly : .open)
            return HabitDayRecord(
                date: today,
                expected: expected,
                done: done,
                state: state,
                vaultDone: vault,
                local: local.map { OverlayValue(value: $0, delivery: .savedOnPhone) }
            )
        }
        // The first of two doses stays on the phone.
        XCTAssertEqual(HabitDosePolicy.change(from: record(done: 0), to: 1, isPast: false), HabitDoseChange(tick: nil, partial: 1))
        // The last one records "done" and clears the count.
        XCTAssertEqual(HabitDosePolicy.change(from: record(done: 1), to: 2, isPast: false), HabitDoseChange(tick: true, partial: nil))
        // Already done on the phone: nothing more to say.
        XCTAssertEqual(HabitDosePolicy.change(from: record(done: 2, local: true), to: 2, isPast: false), HabitDoseChange(tick: nil, partial: nil))
        // One back from done records "off" and keeps one dose.
        XCTAssertEqual(HabitDosePolicy.change(from: record(done: 2, local: true), to: 1, isPast: false), HabitDoseChange(tick: false, partial: 1))
        // Already off: only the count moves.
        XCTAssertEqual(HabitDosePolicy.change(from: record(done: 0, local: false), to: 1, isPast: false), HabitDoseChange(tick: nil, partial: 1))
        // The vault counted more than the phone now says: the phone must win.
        XCTAssertEqual(HabitDosePolicy.change(from: record(done: 2, vault: 2), to: 1, isPast: false), HabitDoseChange(tick: false, partial: 1))
        // Back to nothing today leaves the day open, without an event.
        XCTAssertEqual(HabitDosePolicy.change(from: record(done: 1), to: 0, isPast: false), HabitDoseChange(tick: nil, partial: nil))
        // "Not done" on a day that is over is a fact the vault should hear.
        XCTAssertEqual(HabitDosePolicy.change(from: record(done: 0), to: 0, isPast: true), HabitDoseChange(tick: false, partial: nil))
        // A single-dose habit toggles.
        XCTAssertEqual(HabitDosePolicy.change(from: record(expected: 1, done: 0), to: 1, isPast: false), HabitDoseChange(tick: true, partial: nil))
        XCTAssertEqual(HabitDosePolicy.change(from: record(expected: 1, done: 1, local: true), to: 0, isPast: false), HabitDoseChange(tick: false, partial: nil))
        // Out of range is clamped.
        XCTAssertEqual(HabitDosePolicy.change(from: record(done: 0), to: 9, isPast: false), HabitDoseChange(tick: true, partial: nil))
    }

    func testTheDoseLedgerKeepsCountsAndForgetsOldDays() throws {
        var doses = HabitDoseLedger()
        XCTAssertTrue(doses.isEmpty)
        doses.set(1, on: today, habitID: "holds")
        doses.set(1, on: D.date("2030-09-30"), habitID: "holds")
        doses.set(0, on: today, habitID: "walk")
        XCTAssertEqual(doses.count(on: today, habitID: "holds"), 1)
        XCTAssertNil(doses.count(on: today, habitID: "walk"))

        let restored = HabitDoseLedger(encoded: doses.encoded)
        XCTAssertEqual(restored, doses)

        doses.prune(before: D.date("2030-10-02"))
        XCTAssertNil(doses.count(on: D.date("2030-09-30"), habitID: "holds"))
        XCTAssertEqual(doses.count(on: today, habitID: "holds"), 1)

        doses.set(nil, on: today, habitID: "holds")
        XCTAssertTrue(doses.isEmpty)
        XCTAssertEqual(HabitDoseLedger(encoded: Data("not json".utf8)), .empty)
        XCTAssertEqual(HabitDoseLedger(encoded: nil), .empty)
    }

    // MARK: Back-fill

    func testTheBackFillWindow() {
        XCTAssertTrue(HabitBackfill.allows(today, today: today, windowDays: 14))
        XCTAssertTrue(HabitBackfill.allows(D.date("2030-10-09"), today: today, windowDays: 14))
        XCTAssertFalse(HabitBackfill.allows(D.date("2030-10-08"), today: today, windowDays: 14))
        // A later day is fine (decision A40).
        XCTAssertTrue(HabitBackfill.allows(D.date("2030-10-30"), today: today, windowDays: 14))
        XCTAssertFalse(HabitBackfill.allows(D.date("2030-10-22"), today: today, windowDays: 0))
    }
}
