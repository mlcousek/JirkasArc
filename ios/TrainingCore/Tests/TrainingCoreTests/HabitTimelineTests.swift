// HabitTimelineTests.swift
//
// The habit engine (add-interactive-habits design D2-D5; spec
// training-habits), on synthetic inline fixtures only (HabitFixtures):
//
//   - tolerant decoding of the vault's `streak` / `history` / `adherence`;
//   - a day's state from the history, the plan's day and the phone's tick;
//   - the streak rules (the owner's, 2026-10-01): expected and done
//     extends, expected and missed ends -- a silent past day included --,
//     not expected neither, today not done yet neither;
//   - the fallback without the vault's fields, limited to the days known;
//   - the vault's numbers moved by exactly what the phone knows and the
//     file doesn't (its ticks, a day that ended since);
//   - a habit the vault measures itself: no tick, numbers untouched;
//   - adherence over complete days, where a silent day counts for nothing;
//   - multi-dose days: the phone's dose count and what a counter step
//     records (on/off only on the wire, decision A42);
//   - the back-fill window, and a tick the vault refused.

import XCTest
@testable import TrainingCore

final class HabitTimelineTests: XCTestCase {
    private let today = HabitFixtures.today

    private func timeline(_ id: String, _ snapshot: TrainingSnapshot, today: LocalDate? = nil, doses: HabitDoseLedger = .empty) throws -> HabitTimeline {
        let habit = try XCTUnwrap(snapshot.habits.habit(id))
        return HabitTimeline(habit: habit, snapshot: snapshot, today: today ?? self.today, doses: doses)
    }

    private func state(_ timeline: HabitTimeline, _ date: String) -> HabitDayState? {
        timeline.record(on: D.date(date))?.state
    }

    private func walkDoneToday() -> LoggedEvent {
        HabitFixtures.tick("walk", "2030-10-23", done: true, seq: 1)
    }

    /// The fixture with the vault's fields on the walk.
    private func published(missed: Set<String> = [], unit: String = "day", source: String? = nil) throws -> Data {
        try HabitFixtures.data(ladder: HabitFixtures.ladder(walkExtra: HabitFixtures.published(missed: missed, unit: unit, source: source)))
    }

    // MARK: Decoding

    func testTheVaultsFieldsAreAbsentInAnOlderFile() throws {
        let projection = try HabitFixtures.projection(try HabitFixtures.data())
        let walk = try XCTUnwrap(projection.habits.habit("walk"))
        XCTAssertNil(walk.streak)
        XCTAssertNil(walk.history)
        XCTAssertNil(walk.adherence)
    }

    func testANextStepsEmptyFieldsDecodeAsPublishedNotAbsent() throws {
        // The vault writes `null` / `[]` / `null` on a step that isn't active.
        var extra: [String: Any] = [:]
        extra["streak"] = NSNull()
        extra["history"] = [String]()
        extra["adherence"] = NSNull()
        let projection = try HabitFixtures.projection(try HabitFixtures.data(ladder: HabitFixtures.ladder(walkExtra: extra)))
        let walk = try XCTUnwrap(projection.habits.habit("walk"))
        XCTAssertNil(walk.streak)
        XCTAssertEqual(walk.history, [])
        XCTAssertNil(walk.adherence)
    }

    func testStreakHistoryAndAdherenceDecodeTolerantly() throws {
        let streak: [String: Any] = ["current": 4.0, "best": "many", "unit": "fortnight", "lastDone": "soon"]
        let history: [[String: Any]] = [
            ["date": "2030-10-20", "expected": 2, "done": 2],
            ["date": "2030-10-21", "expected": -1, "done": -5],
            ["date": "not a date", "expected": 1, "done": 1],
            ["date": "2030-10-19", "expected": 2, "done": 1.0],
            ["date": "2030-10-18"]
        ]
        let adherence: [String: Any] = ["d7": 86, "d14": ["pct": 79], "d30": "high", "d84": 140]
        let extra: [String: Any] = ["streak": streak, "history": history, "adherence": adherence]
        let data = try HabitFixtures.data(ladder: HabitFixtures.ladder(holdsExtra: extra))
        let projection = try HabitFixtures.projection(data)
        let holds = try XCTUnwrap(projection.habits.habit("holds"))

        let decoded = try XCTUnwrap(holds.streak)
        XCTAssertEqual(decoded.current, 4)
        XCTAssertNil(decoded.best)
        XCTAssertEqual(decoded.unit, .unknown("fortnight"))
        XCTAssertNil(decoded.lastDone)

        // The entry without a readable date is dropped; the rest are sorted.
        let days = try XCTUnwrap(holds.history)
        XCTAssertEqual(days.map(\.date.description), ["2030-10-18", "2030-10-19", "2030-10-20", "2030-10-21"])
        XCTAssertNil(days[0].expected)
        XCTAssertNil(days[0].done)
        XCTAssertEqual(days[1].expected, 2)
        XCTAssertEqual(days[1].done, 1)
        XCTAssertEqual(days[2].done, 2)
        // A negative count reads as 0.
        XCTAssertEqual(days[3].expected, 0)
        XCTAssertEqual(days[3].done, 0)

        // A percent stays inside 0...100; anything but a number is no percent.
        XCTAssertEqual(holds.adherence, HabitAdherence(d7: 86, d14: nil, d30: nil, d84: 100))
        XCTAssertEqual(holds.adherence?.percent(days: 7), 86)
        XCTAssertNil(holds.adherence?.percent(days: 21))

        let line = try timeline("holds", TrainingSnapshot(projection: projection))
        // Before the history's first entry the plan's own day answers.
        XCTAssertEqual(state(line, "2030-10-17"), .done)
        // Listed without counts: the plan's day says two were expected, and
        // nothing was logged -- a silent day, a miss.
        XCTAssertEqual(state(line, "2030-10-18"), .missed)
        XCTAssertEqual(line.record(on: D.date("2030-10-18"))?.isSilent, true)
        XCTAssertEqual(state(line, "2030-10-19"), .partly)
        XCTAssertEqual(state(line, "2030-10-20"), .done)
        XCTAssertEqual(line.record(on: D.date("2030-10-20"))?.done, 2)
        XCTAssertEqual(state(line, "2030-10-21"), .notExpected)
        // The file's own day is not in the history until it is logged there:
        // the plan's day answers.
        XCTAssertEqual(state(line, "2030-10-22"), .done)
        XCTAssertEqual(state(line, "2030-10-23"), .open)
        // A unit this build doesn't know: the vault's count, never moved.
        XCTAssertEqual(line.streak.current, 4)
        XCTAssertEqual(line.streak.best, 4)
        XCTAssertEqual(line.streak.unit, .occurrence)
        XCTAssertEqual(line.streak.source, .vault)
    }

    // MARK: Days

    func testADaysStateFromThePlan() throws {
        let snapshot = try HabitFixtures.snapshot()
        let walk = try timeline("walk", snapshot)
        XCTAssertEqual(walk.records.count, HabitTimeline.span)
        XCTAssertEqual(walk.records.count, 85)
        XCTAssertEqual(walk.records.last?.date, today)
        XCTAssertEqual(walk.vaultRecords.count, 85)
        XCTAssertEqual(state(walk, "2030-10-16"), .missed)
        XCTAssertEqual(state(walk, "2030-10-22"), .done)
        // Today is expected and not done yet: open, not missed.
        XCTAssertEqual(state(walk, "2030-10-23"), .open)
        // Before the plan's window nothing is known.
        XCTAssertEqual(state(walk, "2030-10-06"), .unknown)
        XCTAssertEqual(walk.knownDays, 17)
        XCTAssertFalse(walk.hasVaultHistory)
        XCTAssertNil(walk.record(on: D.date("2030-10-24")))

        let gym = try timeline("gym", snapshot)
        XCTAssertEqual(state(gym, "2030-10-21"), .done)
        XCTAssertEqual(state(gym, "2030-10-22"), .notExpected)
        XCTAssertEqual(state(gym, "2030-10-10"), .missed)

        let holds = try timeline("holds", snapshot)
        XCTAssertEqual(holds.perDay, 2)
        XCTAssertEqual(state(holds, "2030-10-11"), .partly)
        // An uncapped count of four is simply done.
        XCTAssertEqual(state(holds, "2030-10-13"), .done)
        XCTAssertEqual(state(holds, "2030-10-16"), .missed)
    }

    func testASilentPastExpectedDayIsAMissAndBreaksTheStreak() throws {
        // The 20th was expected and nothing was logged on it, anywhere.
        let data = try HabitFixtures.data { date, day in
            if date == D.date("2030-10-20") { day["habitsDone"] = NSNull() }
        }
        let walk = try timeline("walk", try HabitFixtures.snapshot(data))
        XCTAssertEqual(state(walk, "2030-10-20"), .missed)
        XCTAssertEqual(walk.record(on: D.date("2030-10-20"))?.isSilent, true)
        // Only the 21st and 22nd are left, and the count is exact.
        XCTAssertEqual(walk.streak.current, 2)
        XCTAssertFalse(walk.streak.isAtLeast)
        // Adherence keeps the gate's arithmetic: unrecorded is not zero.
        XCTAssertEqual(HabitTimeline.tally(walk.records, window: 7, today: today), HabitTally(done: 5, expected: 6))
        XCTAssertEqual(walk.adherence.map(\.pct), [83, 92, nil, nil])
    }

    // MARK: Streak rules (the fallback)

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
        XCTAssertEqual(gym.streak.best, 3)
        XCTAssertEqual(gym.streak.unit, .occurrence)
        XCTAssertFalse(gym.streak.isAtLeast)
    }

    func testARunThatReachesTheEdgeOfWhatThePhoneKnowsIsAtLeast() throws {
        let data = try HabitFixtures.data { date, day in
            guard date == D.date("2030-10-10"), var done = day["habitsDone"] as? [String: Int] else { return }
            done["gym"] = 1
            day["habitsDone"] = done
        }
        let gym = try timeline("gym", try HabitFixtures.snapshot(data))
        XCTAssertEqual(gym.streak.current, 5)
        XCTAssertTrue(gym.streak.isAtLeast)
    }

    func testATickTodayExtendsTheStreakImmediately() throws {
        let walk = try timeline("walk", try HabitFixtures.snapshot(ticks: [walkDoneToday()]))
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
        XCTAssertEqual(walk.streak.best, 7)
    }

    func testADoneTickOutsideThePlansWindowStillCounts() throws {
        let snapshot = try HabitFixtures.snapshot(ticks: [HabitFixtures.tick("walk", "2030-10-06", done: true, seq: 1)])
        XCTAssertEqual(state(try timeline("walk", snapshot), "2030-10-06"), .done)
    }

    // MARK: The vault's numbers and what the phone knows on top

    func testTheVaultsNumbersAreShownUntouchedWithoutTicks() throws {
        let walk = try timeline("walk", try HabitFixtures.snapshot(try published()))
        XCTAssertTrue(walk.hasVaultHistory)
        XCTAssertEqual(walk.knownDays, 84)
        XCTAssertEqual(walk.streak.current, 120)
        XCTAssertEqual(walk.streak.best, 130)
        XCTAssertEqual(walk.streak.unit, .day)
        XCTAssertEqual(walk.streak.source, .vault)
        XCTAssertFalse(walk.streak.isAtLeast)
        XCTAssertEqual(walk.streak.lastDone, D.date("2030-10-22"))
        XCTAssertEqual(walk.adherence.map(\.days), [7, 14, 30, 84])
        XCTAssertEqual(walk.adherence.map(\.pct), [100, 100, 100, 100])
        XCTAssertTrue(walk.adherence.allSatisfy { !$0.isEstimate })
    }

    func testATickTodayMovesTheVaultsStreakByOne() throws {
        let walk = try timeline("walk", try HabitFixtures.snapshot(try published(), ticks: [walkDoneToday()]))
        XCTAssertEqual(walk.streak.current, 121)
        XCTAssertEqual(walk.streak.best, 130)
        XCTAssertEqual(walk.streak.source, .vaultWithPhoneTicks)
        XCTAssertEqual(walk.streak.lastDone, today)
        // Adherence covers complete days only: today's tick never moves it.
        XCTAssertEqual(walk.adherence.map(\.pct), [100, 100, 100, 100])
        XCTAssertTrue(walk.adherence.allSatisfy { !$0.isEstimate })
    }

    func testANewBestFollowsTheCurrentStreak() throws {
        var streak: [String: Any] = [:]
        streak["current"] = 120
        streak["best"] = 120
        streak["unit"] = "day"
        var extra: [String: Any] = [:]
        extra["streak"] = streak
        extra["history"] = HabitFixtures.history()
        let data = try HabitFixtures.data(ladder: HabitFixtures.ladder(walkExtra: extra))
        let snapshot = try HabitFixtures.snapshot(data, ticks: [walkDoneToday()])
        XCTAssertEqual(try timeline("walk", snapshot).streak.best, 121)
    }

    func testUntickingAPastDayBreaksTheVaultsStreak() throws {
        let snapshot = try HabitFixtures.snapshot(try published(), ticks: [HabitFixtures.tick("walk", "2030-10-20", done: false, seq: 1)])
        let walk = try timeline("walk", snapshot)
        // Only the 21st and 22nd are left.
        XCTAssertEqual(walk.streak.current, 2)
        XCTAssertEqual(walk.streak.best, 130)
        XCTAssertEqual(walk.streak.source, .vaultWithPhoneTicks)
        XCTAssertFalse(walk.streak.isAtLeast)
        // Each window holds that day: the vault's percent moves by what the
        // phone's own count moved (6 of 7, 13 of 14, 29 of 30, 82 of 83).
        XCTAssertEqual(walk.adherence.map(\.pct), [85, 92, 96, 98])
        XCTAssertTrue(walk.adherence.allSatisfy(\.isEstimate))
    }

    func testAStreakTheVaultBrokeIsMovedByTheSameDifference() throws {
        // The vault's history has a miss on the 12th and its streak says 10.
        var streak: [String: Any] = [:]
        streak["current"] = 10
        streak["best"] = 40
        streak["unit"] = "occurrence"
        var extra: [String: Any] = [:]
        extra["streak"] = streak
        extra["history"] = HabitFixtures.history(missed: ["2030-10-12"])
        let data = try HabitFixtures.data(ladder: HabitFixtures.ladder(walkExtra: extra))
        let untouched = try timeline("walk", try HabitFixtures.snapshot(data))
        XCTAssertEqual(state(untouched, "2030-10-12"), .missed)
        XCTAssertEqual(untouched.streak.current, 10)
        XCTAssertEqual(untouched.streak.unit, .occurrence)
        XCTAssertEqual(untouched.streak.source, .vault)
        let ticked = try timeline("walk", try HabitFixtures.snapshot(data, ticks: [walkDoneToday()]))
        XCTAssertEqual(ticked.streak.current, 11)
        XCTAssertEqual(ticked.streak.best, 40)
    }

    func testAWeekStreakIsNeverRecountedOnThePhone() throws {
        let snapshot = try HabitFixtures.snapshot(try published(unit: "week"), ticks: [walkDoneToday()])
        let walk = try timeline("walk", snapshot)
        XCTAssertEqual(walk.streak.current, 120)
        XCTAssertEqual(walk.streak.unit, .week)
        XCTAssertEqual(walk.streak.source, .vault)
        // The day itself still shows the tick.
        XCTAssertEqual(state(walk, "2030-10-23"), .done)
    }

    func testADayThatEndedSilentSinceTheFileWasWrittenBreaksTheStreak() throws {
        // The file is the one written for the 22nd; the phone's day is now
        // the 24th and nothing was logged on the 23rd.
        let tomorrow = D.date("2030-10-24")
        let silent = try timeline("walk", try HabitFixtures.snapshot(try published()), today: tomorrow)
        XCTAssertEqual(state(silent, "2030-10-23"), .missed)
        XCTAssertEqual(state(silent, "2030-10-24"), .open)
        XCTAssertEqual(silent.streak.current, 0)
        XCTAssertEqual(silent.streak.best, 130)
        XCTAssertEqual(silent.streak.source, .vaultWithPhoneTicks)
        // The file itself still sees the 23rd as open.
        XCTAssertEqual(silent.vaultRecords.first { $0.date == D.date("2030-10-23") }?.state, .open)

        // Back-filling the 23rd joins the run again, and today extends it.
        let filled = try timeline("walk", try HabitFixtures.snapshot(try published(), ticks: [walkDoneToday()]), today: tomorrow)
        XCTAssertEqual(filled.streak.current, 121)
        let both = try timeline(
            "walk",
            try HabitFixtures.snapshot(try published(), ticks: [walkDoneToday(), HabitFixtures.tick("walk", "2030-10-24", done: true, seq: 2)]),
            today: tomorrow
        )
        XCTAssertEqual(both.streak.current, 122)
        XCTAssertEqual(both.streak.lastDone, tomorrow)
    }

    func testAHabitTheVaultMeasuresTakesNoTickAndKeepsItsNumbers() throws {
        let data = try published(source: "activity")
        let habit = try XCTUnwrap(try HabitFixtures.projection(data).habits.habit("walk"))
        XCTAssertTrue(HabitBackfill.isMeasured(habit))

        // A tick of the phone means nothing to it.
        let ticked = try timeline("walk", try HabitFixtures.snapshot(data, ticks: [walkDoneToday()]))
        XCTAssertEqual(state(ticked, "2030-10-23"), .open)
        XCTAssertEqual(ticked.streak.current, 120)
        XCTAssertEqual(ticked.streak.source, .vault)

        // A day after the file's is the vault's to judge: open, never a miss.
        let later = try timeline("walk", try HabitFixtures.snapshot(data), today: D.date("2030-10-24"))
        XCTAssertEqual(state(later, "2030-10-23"), .open)
        XCTAssertEqual(later.streak.current, 120)
        XCTAssertEqual(later.streak.source, .vault)

        // No `source` (or one this build doesn't know) is tickable.
        let plain = try XCTUnwrap(try HabitFixtures.projection(try HabitFixtures.data()).habits.habit("walk"))
        XCTAssertFalse(HabitBackfill.isMeasured(plain))
    }

    // MARK: Adherence

    func testFallbackAdherenceCoversOnlyTheWindowsThePhoneKnows() throws {
        let walk = try timeline("walk", try HabitFixtures.snapshot())
        // 17 known days: 7 and 14 are counted (6 of 7, 13 of 14), 30 and 84
        // are not.
        XCTAssertEqual(walk.adherence.map(\.days), [7, 14, 30, 84])
        XCTAssertEqual(walk.adherence.map(\.pct), [85, 92, nil, nil])
        XCTAssertTrue(walk.adherence.allSatisfy(\.isEstimate))

        let holds = try timeline("holds", try HabitFixtures.snapshot())
        // Doses capped at the day's two: 9 of 14, 21 of 28.
        XCTAssertEqual(holds.adherence.map(\.pct), [64, 75, nil, nil])
    }

    func testAdherenceCoversCompleteDaysOnly() throws {
        let walk = try timeline("walk", try HabitFixtures.snapshot())
        // 16 ... 22 October: the 16th was missed.
        XCTAssertEqual(HabitTimeline.tally(walk.records, window: 7, today: today), HabitTally(done: 6, expected: 7))
        XCTAssertEqual(HabitTally(done: 6, expected: 7).pct, 85)
        // Today's tick is not in it.
        let ticked = try timeline("walk", try HabitFixtures.snapshot(ticks: [walkDoneToday()]))
        XCTAssertEqual(HabitTimeline.tally(ticked.records, window: 7, today: today), HabitTally(done: 6, expected: 7))
        // Yesterday alone.
        XCTAssertEqual(HabitTimeline.tally(walk.records, window: 1, today: today), HabitTally(done: 1, expected: 1))
        // A back-filled day is.
        let filled = try timeline("walk", try HabitFixtures.snapshot(ticks: [HabitFixtures.tick("walk", "2030-10-16", done: true, seq: 1)]))
        XCTAssertEqual(filled.adherence.map(\.pct), [100, 100, nil, nil])
    }

    func testTheGatesWindowIsThe14DayNumberWhenTheVaultPublishesOnlyThat() throws {
        let window: [String: Int] = ["done": 11, "expected": 14, "pct": 78, "recordedDays": 14]
        var extra: [String: Any] = [:]
        extra["window14"] = window
        let data = try HabitFixtures.data(ladder: HabitFixtures.ladder(walkExtra: extra))
        let walk = try timeline("walk", try HabitFixtures.snapshot(data))
        XCTAssertEqual(walk.adherence[1], HabitAdherenceValue(days: 14, pct: 78, isEstimate: false))
        // The other windows are the phone's own.
        XCTAssertEqual(walk.adherence[0], HabitAdherenceValue(days: 7, pct: 85, isEstimate: true))
        // Today's tick doesn't move it; a back-filled day inside it does, by
        // the phone's own difference (13 of 14 -> 14 of 14: +8).
        let ticked = try timeline("walk", try HabitFixtures.snapshot(data, ticks: [walkDoneToday()]))
        XCTAssertEqual(ticked.adherence[1], HabitAdherenceValue(days: 14, pct: 78, isEstimate: false))
        let filled = try timeline("walk", try HabitFixtures.snapshot(data, ticks: [HabitFixtures.tick("walk", "2030-10-16", done: true, seq: 1)]))
        XCTAssertEqual(filled.adherence[1], HabitAdherenceValue(days: 14, pct: 86, isEstimate: true))
    }

    // MARK: Multi-dose days

    func testDosesOnTheDayFromTheVaultThePhonesCountAndItsTick() throws {
        let partlyToday = try HabitFixtures.data { date, day in
            if date == D.date("2030-10-23") {
                let counts: [String: Int] = ["holds": 1]
                day["habitsDone"] = counts
            }
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

    // MARK: Back-fill and refusals

    func testTheBackFillWindowIsTodayAndFourteenDaysBack() {
        XCTAssertEqual(HabitBackfill.windowDays, 14)
        XCTAssertTrue(HabitBackfill.allows(today, today: today))
        XCTAssertTrue(HabitBackfill.allows(D.date("2030-10-09"), today: today))
        XCTAssertFalse(HabitBackfill.allows(D.date("2030-10-08"), today: today))
        // The vault refuses a day that hasn't come.
        XCTAssertFalse(HabitBackfill.allows(D.date("2030-10-24"), today: today))
    }

    func testATickTheVaultRefusedIsNotLaidOverThePlan() throws {
        // The phone ticked the 1st (22 days back); the vault refused it.
        let data = try HabitFixtures.data(outcomes: [HabitFixtures.refusal(seq: 2)])
        let ticks = [
            HabitFixtures.tick("walk", "2030-10-16", done: true, seq: 1),
            HabitFixtures.tick("walk", "2030-10-01", done: true, seq: 2)
        ]
        let snapshot = try HabitFixtures.snapshot(data, ticks: ticks)
        let overlay = snapshot.checkIns
        XCTAssertNil(overlay.habitTick(on: D.date("2030-10-01"), habitId: "walk"))
        let refusal = try XCTUnwrap(overlay.refusedHabitTick(on: D.date("2030-10-01"), habitId: "walk"))
        XCTAssertEqual(refusal.reason.resolvedText(.english), "That day is more than 14 days back.")
        XCTAssertEqual(refusal.reason.resolvedText(.czech), "Ten den je víc než 14 dní zpátky.")
        // The accepted tick is untouched.
        XCTAssertEqual(overlay.habitTick(on: D.date("2030-10-16"), habitId: "walk")?.value, true)
        XCTAssertNil(overlay.refusedHabitTick(on: D.date("2030-10-16"), habitId: "walk"))
        XCTAssertEqual(overlay.refusedHabitTicks.count, 1)
        // The refused day shows what the plan knows of it: nothing.
        XCTAssertEqual(state(try timeline("walk", snapshot), "2030-10-01"), .unknown)
    }

    func testARefusalOnlyTakesTheTickItNames() throws {
        // The same day was ticked twice; only the second was refused, so the
        // first stays what the day shows. A refusal of another device's
        // event, or of another type, names nothing here.
        var foreign = HabitFixtures.refusal(seq: 1)
        foreign["event"] = "someone-elses-event"
        foreign["deviceId"] = "ios-0000cafe"
        var planCommand = HabitFixtures.refusal(seq: 1)
        planCommand["type"] = "plan.session.moved"
        let outcomes = PlanOutcome.parse(try HabitFixtures.projection(
            try HabitFixtures.data(outcomes: [foreign, planCommand, HabitFixtures.refusal(seq: 2, reason: nil)])
        ).outcomes)
        XCTAssertEqual(outcomes.count, 3)
        let ticks = [
            HabitFixtures.tick("walk", "2030-10-16", done: true, seq: 1),
            HabitFixtures.tick("walk", "2030-10-16", done: false, seq: 2)
        ]
        let overlay = CheckInOverlay.fold(ticks, unsentSegments: [], outcomes: outcomes)
        XCTAssertEqual(overlay.habitTick(on: D.date("2030-10-16"), habitId: "walk")?.value, true)
        let refusal = try XCTUnwrap(overlay.refusedHabitTick(on: D.date("2030-10-16"), habitId: "walk"))
        XCTAssertNil(refusal.reason)

        // A later accepted tick of that day clears the refusal.
        let again = ticks + [HabitFixtures.tick("walk", "2030-10-16", done: false, seq: 3)]
        let cleared = CheckInOverlay.fold(again, unsentSegments: [], outcomes: outcomes)
        XCTAssertEqual(cleared.habitTick(on: D.date("2030-10-16"), habitId: "walk")?.value, false)
        XCTAssertNil(cleared.refusedHabitTick(on: D.date("2030-10-16"), habitId: "walk"))

        // Without outcomes every tick is laid over the plan, as before.
        let plain = CheckInOverlay.fold(ticks, unsentSegments: [])
        XCTAssertEqual(plain.habitTick(on: D.date("2030-10-16"), habitId: "walk")?.value, false)
        XCTAssertTrue(plain.refusedHabitTicks.isEmpty)
    }
}
