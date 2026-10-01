// HabitModelTests.swift
//
// What the Habits screens show (add-interactive-habits design D6-D8; spec
// training-habits), on the synthetic inline fixture (HabitFixtures): the
// ladder as established / current / locked steps, one habit's detail
// (today's control, streak, adherence tiles, the 12-week calendar, recent
// entries), when a day can be changed and why not, Today's checks and the
// all-done state, the shortcut's choices, and the Czech wording.

import XCTest
@testable import TrainingCore

final class HabitModelTests: XCTestCase {
    private let today = HabitFixtures.today

    private func builder(
        _ snapshot: TrainingSnapshot,
        _ language: TrainingLanguage = .english,
        doses: HabitDoseLedger = .empty
    ) -> HabitsBuilder {
        HabitsBuilder(source: .loaded(snapshot), language: language, today: today, doses: doses)
    }

    private func walkDone() -> LoggedEvent {
        HabitFixtures.tick("walk", "2030-10-23", done: true, seq: 1)
    }

    // MARK: The ladder

    func testTheLadderAsSteps() throws {
        let screen = builder(try HabitFixtures.snapshot()).screen()
        XCTAssertNil(screen.emptyText)
        XCTAssertEqual(screen.stepText, "Step 3 of 5")
        XCTAssertEqual(screen.gateText, "Gate: 80 % · 14-day window")
        // Wednesday: holds and the walk, not the gym.
        XCTAssertEqual(screen.progressText, "0 of 2 done today")
        XCTAssertEqual(screen.steps.map(\.id), ["holds", "gym", "walk", "stretch", "swim"])
        XCTAssertEqual(screen.steps.map(\.kind), [.established, .established, .current, .locked, .locked])
        XCTAssertEqual(screen.steps.map(\.kindText), ["Established", "Established", "Current step", "Locked", "Locked"])
        XCTAssertEqual(screen.steps.map(\.stepText), ["Step 1", "Step 2", "Step 3", "Step 4", "Step 5"])

        let walk = screen.steps[2]
        XCTAssertEqual(walk.label, "Morning walk")
        XCTAssertEqual(walk.schedule, "Every day")
        XCTAssertEqual(walk.streak?.currentText, "6 days in a row")
        XCTAssertEqual(walk.today?.stateText, "Not done yet")
        XCTAssertNil(walk.unlockText)
        XCTAssertEqual(walk.accessibilityLabel, "Morning walk, Current step, 6 days in a row, Not done yet")

        // Not expected on a Wednesday: a streak, no control.
        let gym = screen.steps[1]
        XCTAssertEqual(gym.streak?.currentText, "3× in a row")
        XCTAssertNil(gym.today)
        XCTAssertEqual(screen.steps[0].today?.isMultiDose, true)

        let stretch = screen.steps[3]
        XCTAssertNil(stretch.streak)
        XCTAssertNil(stretch.today)
        XCTAssertEqual(stretch.unlockText, "Unlocks when Morning walk holds 80 % over a 14-day window")
        XCTAssertEqual(screen.steps[4].unlockText, "Unlocks after: Stretch after easy runs")
    }

    func testGateMetUnlocksTheNextStep() throws {
        let data = try HabitFixtures.data(ladder: HabitFixtures.ladder(walkExtra: ["gateMet": true]))
        let screen = builder(try HabitFixtures.snapshot(data)).screen()
        XCTAssertEqual(screen.steps[2].gateMetText, "Gate met: the next habit can start at your Sunday review")
        XCTAssertEqual(screen.steps[3].unlockText, "Gate met: the next habit can start at your Sunday review")
    }

    func testNoLadderAndNoPlan() throws {
        let empty = builder(try HabitFixtures.snapshot(try HabitFixtures.data(ladder: []))).screen()
        XCTAssertEqual(empty.emptyText, "No habits in this plan")
        XCTAssertTrue(empty.steps.isEmpty)
        let waiting = HabitsBuilder(source: .waitingForFirstSync, language: .english, today: today)
        XCTAssertEqual(waiting.screen().emptyText, "No habits in this plan")
        XCTAssertNil(waiting.detail(habitID: "walk"))
        XCTAssertNil(waiting.dayControl(habitID: "walk", date: today))
        XCTAssertFalse(waiting.todayChecks(on: today).allDone)
    }

    // MARK: One habit

    func testDetailOfAnActiveHabitFromThePhonesOwnCount() throws {
        let detail = try XCTUnwrap(builder(try HabitFixtures.snapshot()).detail(habitID: "walk"))
        XCTAssertEqual(detail.label, "Morning walk")
        XCTAssertEqual(detail.kind, .current)
        XCTAssertEqual(detail.gateText, "Gate: 80 % · 14-day window")
        XCTAssertEqual(detail.backfillDays, 14)

        XCTAssertEqual(detail.streak.current, 6)
        XCTAssertEqual(detail.streak.currentText, "6 days in a row")
        XCTAssertEqual(detail.streak.bestText, "Best: 7")
        XCTAssertEqual(detail.streak.bestRunText, "7 days in a row")
        XCTAssertTrue(detail.streak.isLit)
        XCTAssertEqual(detail.streak.lastDoneText, "Last done Tue 22 Oct")
        // Said plainly: the phone counted, and over how many days.
        XCTAssertEqual(detail.streak.estimateText, "Counted on the phone from the last 17 days it knows")
        XCTAssertNil(detail.streak.mayBeLongerText)

        XCTAssertEqual(detail.adherenceTitle, "Adherence")
        XCTAssertEqual(detail.adherence.map(\.title), ["7 d", "14 d", "30 d", "84 d"])
        XCTAssertEqual(detail.adherence.map(\.valueText), ["100 %", "92 %", "–", "–"])
        XCTAssertEqual(detail.adherence.map(\.meetsGate), [true, true, nil, nil])
        XCTAssertEqual(detail.adherence[0].accessibilityLabel, "7 d: 100 %")
        XCTAssertEqual(detail.adherence[2].accessibilityLabel, "30 d: No record")
        XCTAssertEqual(detail.adherenceNote, "Longer windows fill in once the vault publishes the habit's history.")

        let control = try XCTUnwrap(detail.today)
        XCTAssertEqual(control.dateText, "Today")
        XCTAssertEqual(control.stateText, "Not done yet")
        XCTAssertEqual(control.state, .open)
        XCTAssertTrue(control.canRecord)
        XCTAssertFalse(control.isMultiDose)
        XCTAssertFalse(control.isPending)
        XCTAssertNil(control.deliveryText)
        XCTAssertEqual(control.tapTarget, 1)
        XCTAssertEqual(control.change(to: control.tapTarget), HabitDoseChange(tick: true, partial: nil))
    }

    func testTheCalendarIsTwelveWeeksEndingWithThisWeek() throws {
        let detail = try XCTUnwrap(builder(try HabitFixtures.snapshot()).detail(habitID: "walk"))
        let calendar = detail.calendar
        XCTAssertEqual(calendar.title, "Last 12 weeks")
        XCTAssertEqual(calendar.weekdayHeaders, ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"])
        XCTAssertEqual(calendar.weeks.count, 12)
        XCTAssertTrue(calendar.weeks.allSatisfy { $0.cells.count == 7 })
        XCTAssertEqual(calendar.weeks.first?.monday, D.date("2030-08-05"))
        XCTAssertEqual(calendar.weeks.last?.monday, D.date("2030-10-21"))
        XCTAssertEqual(calendar.weeks.last?.label, "21 Oct")
        XCTAssertEqual(calendar.legend.map(\.text), ["Done", "Partly", "Missed", "Not planned", "No record"])
        XCTAssertEqual(calendar.hint, "Tap a day to fill it in. Back-fill window: 14 d.")

        let thisWeek = try XCTUnwrap(calendar.weeks.last).cells
        XCTAssertEqual(thisWeek.map(\.state), [.done, .done, .open, nil, nil, nil, nil])
        XCTAssertEqual(thisWeek.map(\.isToday), [false, false, true, false, false, false, false])
        XCTAssertEqual(thisWeek[2].dayText, "23")
        XCTAssertEqual(thisWeek[2].accessibilityLabel, "Wed 23 Oct: Not done yet")
        // A later day is only a date.
        XCTAssertEqual(thisWeek[3].accessibilityLabel, "Thu 24 Oct")
        XCTAssertFalse(thisWeek[3].isInBackfillWindow)

        let lastWeek = calendar.weeks[10].cells
        XCTAssertEqual(lastWeek[2].state, .missed)
        XCTAssertEqual(lastWeek[2].accessibilityLabel, "Wed 16 Oct: Missed")
        // The window reaches back to the 9th.
        let twoWeeksAgo = calendar.weeks[9].cells
        XCTAssertEqual(twoWeeksAgo.map(\.isInBackfillWindow), [false, false, true, true, true, true, true])
        // Before the plan's window: no record.
        XCTAssertEqual(calendar.weeks[0].cells[0].state, .unknown)
        XCTAssertEqual(calendar.weeks[0].cells[0].accessibilityLabel, "Mon 5 Aug: No record")
    }

    func testRecentEntriesNewestFirst() throws {
        let detail = try XCTUnwrap(builder(try HabitFixtures.snapshot()).detail(habitID: "walk"))
        XCTAssertEqual(detail.logTitle, "Recent entries")
        XCTAssertNil(detail.logEmptyText)
        XCTAssertEqual(detail.log.count, HabitsBuilder.logLimit)
        XCTAssertEqual(detail.log[0].dateText, "Tue 22 Oct")
        XCTAssertEqual(detail.log[0].stateText, "Done")
        XCTAssertEqual(detail.log[6].dateText, "Wed 16 Oct")
        XCTAssertEqual(detail.log[6].stateText, "Missed")
        XCTAssertNil(detail.log[0].deliveryText)

        // The phone's own tick leads the list and says where it is.
        let segment = UUID()
        let ticked = try HabitFixtures.snapshot(ticks: [
            HabitFixtures.tick("walk", "2030-10-23", done: true, seq: 1),
            HabitFixtures.tick("walk", "2030-10-16", done: true, seq: 2, segment: segment)
        ])
        let after = try XCTUnwrap(builder(ticked).detail(habitID: "walk"))
        XCTAssertEqual(after.log[0].dateText, "Wed 23 Oct")
        XCTAssertEqual(after.log[0].deliveryText, "Saved on phone")
        XCTAssertEqual(after.log[7].dateText, "Wed 16 Oct")
        XCTAssertEqual(after.log[7].stateText, "Done")
        XCTAssertEqual(after.log[7].deliveryText, "Sent")
        XCTAssertEqual(after.today?.isPending, true)
        XCTAssertEqual(after.today?.deliveryText, "Saved on phone")
        XCTAssertEqual(after.streak.currentText, "15 days in a row")
    }

    func testALockedHabitHasNoControlAndSaysWhatUnlocksIt() throws {
        let detail = try XCTUnwrap(builder(try HabitFixtures.snapshot()).detail(habitID: "stretch"))
        XCTAssertEqual(detail.kind, .locked)
        XCTAssertEqual(detail.kindText, "Locked")
        XCTAssertNil(detail.today)
        XCTAssertEqual(detail.unlockText, "Unlocks when Morning walk holds 80 % over a 14-day window")
        XCTAssertEqual(detail.streak.currentText, "No streak yet")
        XCTAssertFalse(detail.streak.isLit)
        XCTAssertNil(detail.calendar.hint)
        XCTAssertEqual(detail.logEmptyText, "Nothing logged yet")
        XCTAssertNil(builder(try HabitFixtures.snapshot()).detail(habitID: "nope"))
    }

    func testTheVaultsNumbersAreShownWithoutAnEstimateNote() throws {
        let data = try HabitFixtures.data(ladder: HabitFixtures.ladder(walkExtra: [
            "streak": ["current": 120, "best": 130, "unit": "day", "lastDone": "2030-10-22"],
            "history": HabitFixtures.history(),
            "adherence": ["d7": 100, "d14": 93, "d30": 90, "d84": 88]
        ]))
        let detail = try XCTUnwrap(builder(try HabitFixtures.snapshot(data)).detail(habitID: "walk"))
        XCTAssertEqual(detail.streak.currentText, "120 days in a row")
        XCTAssertEqual(detail.streak.bestText, "Best: 130")
        XCTAssertNil(detail.streak.estimateText)
        XCTAssertEqual(detail.adherence.map(\.valueText), ["100 %", "93 %", "90 %", "88 %"])
        XCTAssertNil(detail.adherenceNote)
        XCTAssertEqual(detail.calendar.weeks[0].cells[0].state, .done)

        let ticked = try XCTUnwrap(builder(try HabitFixtures.snapshot(data, ticks: [walkDone()])).detail(habitID: "walk"))
        XCTAssertEqual(ticked.streak.currentText, "121 days in a row")
    }

    func testAnOpenEndedCountSaysTheStreakMayBeLonger() throws {
        let data = try HabitFixtures.data { date, day in
            guard date == D.date("2030-10-10"), var done = day["habitsDone"] as? [String: Any] else { return }
            done["gym"] = 1
            day["habitsDone"] = done
        }
        let detail = try XCTUnwrap(builder(try HabitFixtures.snapshot(data)).detail(habitID: "gym"))
        XCTAssertEqual(detail.streak.currentText, "5× in a row")
        XCTAssertEqual(detail.streak.mayBeLongerText, "The streak may be longer: the phone doesn't know the days before.")
    }

    // MARK: A day's control

    func testWhenADayCanBeChangedAndWhyNot() throws {
        let snapshot = try HabitFixtures.snapshot()
        let habits = builder(snapshot)

        // The oldest day of the window, and the day before it.
        let edge = try XCTUnwrap(habits.dayControl(habitID: "walk", date: D.date("2030-10-09")))
        XCTAssertTrue(edge.canRecord)
        XCTAssertTrue(edge.isPast)
        XCTAssertEqual(edge.dateText, "Wed 9 Oct")
        let old = try XCTUnwrap(habits.dayControl(habitID: "walk", date: D.date("2030-10-08")))
        XCTAssertFalse(old.canRecord)
        XCTAssertEqual(old.lockedText, "Outside the back-fill window (14 d)")
        XCTAssertEqual(old.stateText, "Missed")

        let notPlanned = try XCTUnwrap(habits.dayControl(habitID: "gym", date: D.date("2030-10-22")))
        XCTAssertFalse(notPlanned.canRecord)
        XCTAssertEqual(notPlanned.stateText, "Not planned")
        XCTAssertEqual(notPlanned.lockedText, "Not on the plan that day")

        let unknown = try XCTUnwrap(habits.dayControl(habitID: "walk", date: D.date("2030-09-30")))
        XCTAssertEqual(unknown.stateText, "No record")
        XCTAssertEqual(unknown.lockedText, "The phone doesn't know that day's plan")

        // A later day can be ticked ahead (decision A40).
        let tomorrow = try XCTUnwrap(habits.dayControl(habitID: "walk", date: D.date("2030-10-24")))
        XCTAssertTrue(tomorrow.canRecord)
        XCTAssertFalse(tomorrow.isPast)
        XCTAssertEqual(tomorrow.state, .open)

        // Filling in a missed day: done, and "not done" on a day that is over.
        let missed = try XCTUnwrap(habits.dayControl(habitID: "walk", date: D.date("2030-10-16")))
        XCTAssertEqual(missed.change(done: true), HabitDoseChange(tick: true, partial: nil))
        XCTAssertEqual(edge.change(done: false), HabitDoseChange(tick: false, partial: nil))
        // Each button is offered only when it would change something.
        XCTAssertTrue(missed.canMarkDone)
        XCTAssertFalse(edge.canMarkDone)
        XCTAssertTrue(edge.canMarkNotDone)
        XCTAssertFalse(old.canMarkDone)
        let todayControl = try XCTUnwrap(habits.dayControl(habitID: "walk", date: today))
        XCTAssertTrue(todayControl.canMarkDone)
        XCTAssertFalse(todayControl.canMarkNotDone)

        let readOnly = builder(try HabitFixtures.snapshot(canRecord: false))
        let locked = try XCTUnwrap(readOnly.dayControl(habitID: "walk", date: today))
        XCTAssertFalse(locked.canRecord)
        XCTAssertEqual(locked.lockedText, "Turn on and test the vault connection to log habits")
        XCTAssertNil(readOnly.detail(habitID: "walk")?.calendar.hint)
    }

    func testTheBackFillWindowIsTheProjections() throws {
        let habits = builder(try HabitFixtures.snapshot(try HabitFixtures.data(backfillDays: 7)))
        XCTAssertEqual(habits.dayControl(habitID: "walk", date: D.date("2030-10-16"))?.canRecord, true)
        XCTAssertEqual(habits.dayControl(habitID: "walk", date: D.date("2030-10-15"))?.lockedText, "Outside the back-fill window (7 d)")
        let detail = try XCTUnwrap(habits.detail(habitID: "walk"))
        XCTAssertEqual(detail.backfillDays, 7)
        XCTAssertEqual(detail.calendar.hint, "Tap a day to fill it in. Back-fill window: 7 d.")
    }

    func testAMultiDoseDayCountsUpAndBack() throws {
        var doses = HabitDoseLedger()
        doses.set(1, on: today, habitID: "holds")
        let half = try XCTUnwrap(builder(try HabitFixtures.snapshot(), doses: doses).dayControl(habitID: "holds", date: today))
        XCTAssertTrue(half.isMultiDose)
        XCTAssertEqual(half.expected, 2)
        XCTAssertEqual(half.done, 1)
        XCTAssertEqual(half.stateText, "1 of 2")
        XCTAssertEqual(half.tapTarget, 2)
        XCTAssertEqual(half.change(to: half.tapTarget), HabitDoseChange(tick: true, partial: nil))

        let done = HabitFixtures.tick("holds", "2030-10-23", done: true, seq: 1)
        let full = try XCTUnwrap(builder(try HabitFixtures.snapshot(ticks: [done])).dayControl(habitID: "holds", date: today))
        XCTAssertEqual(full.done, 2)
        XCTAssertEqual(full.stateText, "Done")
        // One tap on a complete day takes one dose back, never the whole day.
        XCTAssertEqual(full.tapTarget, 1)
        XCTAssertEqual(full.change(to: full.tapTarget), HabitDoseChange(tick: false, partial: 1))

        // The vault's uncapped count never shows more than the day's doses.
        let four = try XCTUnwrap(builder(try HabitFixtures.snapshot()).dayControl(habitID: "holds", date: D.date("2030-10-13")))
        XCTAssertEqual(four.done, 2)
    }

    // MARK: Today's card

    func testTodaysChecksAndTheAllDoneState() throws {
        let before = builder(try HabitFixtures.snapshot()).todayChecks(on: today)
        // The active habits; the gym has a streak and no control today.
        XCTAssertEqual(before.checks.keys.sorted(), ["gym", "holds", "walk"])
        XCTAssertNil(before.check("gym")?.control)
        XCTAssertEqual(before.check("gym")?.streakCount, 3)
        XCTAssertEqual(before.check("walk")?.streakText, "6 days in a row")
        XCTAssertEqual(before.check("walk")?.streakIsLit, true)
        XCTAssertEqual(before.check("walk")?.control?.canRecord, true)
        XCTAssertFalse(before.allDone)
        XCTAssertEqual(before.progressText, "0 of 2 done today")
        XCTAssertEqual(before.allDoneText, "All of today's habits done")

        let oneLeft = builder(try HabitFixtures.snapshot(ticks: [walkDone()])).todayChecks(on: today)
        XCTAssertEqual(oneLeft.check("walk")?.streakCount, 7)
        XCTAssertEqual(oneLeft.check("walk")?.control?.isDone, true)
        XCTAssertFalse(oneLeft.allDone)

        let both = builder(try HabitFixtures.snapshot(ticks: [walkDone(), HabitFixtures.tick("holds", "2030-10-23", done: true, seq: 2)]))
        XCTAssertTrue(both.todayChecks(on: today).allDone)
        XCTAssertEqual(both.todayChecks(on: today).progressText, "2 of 2 done today")
        // One of two doses is not a done habit.
        var doses = HabitDoseLedger()
        doses.set(1, on: today, habitID: "holds")
        let half = builder(try HabitFixtures.snapshot(ticks: [walkDone()]), doses: doses).todayChecks(on: today)
        XCTAssertEqual(half.doneCount, 1)
        XCTAssertEqual(half.expectedCount, 2)
        XCTAssertFalse(half.allDone)
        XCTAssertEqual(both.screen().progressText, "2 of 2 done today")

        // The day switcher on Monday: the gym is expected and done.
        let monday = builder(try HabitFixtures.snapshot()).todayChecks(on: D.date("2030-10-21"))
        XCTAssertEqual(monday.check("gym")?.control?.stateText, "Done")
        XCTAssertEqual(monday.check("holds")?.control?.stateText, "Missed")
        XCTAssertFalse(monday.allDone)
    }

    // MARK: Czech

    func testCzechWording() throws {
        let habits = builder(try HabitFixtures.snapshot(), .czech)
        let walk = try XCTUnwrap(habits.detail(habitID: "walk"))
        XCTAssertEqual(walk.label, "Ranní procházka")
        XCTAssertEqual(walk.streak.currentText, "6 dní v řadě")
        XCTAssertEqual(walk.streak.bestText, "Nejlepší: 7")
        XCTAssertEqual(walk.streak.estimateText, "Počítáno v telefonu z posledních 17 dnů, které zná")
        XCTAssertEqual(walk.today?.stateText, "Zatím nesplněno")
        XCTAssertEqual(walk.today?.dateText, "Dnes")
        XCTAssertEqual(walk.adherence[1].valueText, "92 %")
        XCTAssertEqual(walk.calendar.title, "Posledních 12 týdnů")
        XCTAssertEqual(walk.kindText, "Aktuální krok")
        XCTAssertEqual(try XCTUnwrap(habits.detail(habitID: "gym")).streak.currentText, "3× v řadě")
        XCTAssertEqual(try XCTUnwrap(habits.detail(habitID: "holds")).streak.currentText, "1 den v řadě")
        XCTAssertEqual(habits.screen().steps[4].unlockText, "Odemkne se po kroku: Protažení po klidném běhu")

        let text = TrainingText(.czech)
        XCTAssertEqual(text.format(.habitStreakDays, 3), "3 dny v řadě")
        XCTAssertEqual(text.format(.habitStreakWeeks, 2), "2 týdny v řadě")
        XCTAssertEqual(text.format(.habitStreakWeeks, 12), "12 týdnů v řadě")
        XCTAssertEqual(text.format(.habitEstimateNote, 1), "Počítáno v telefonu z posledního 1 dne, který zná")
        XCTAssertEqual(text.format(.habitLockedWindow, 14), "Mimo okno pro doplnění (14 d)")
        XCTAssertEqual(TrainingText(.english).format(.habitStreakDays, 1), "1 day in a row")
    }

    // MARK: The shortcut

    func testTheShortcutOffersActiveHabitsAndTicksTodaysTrainingDay() throws {
        let projection = try HabitFixtures.projection(try HabitFixtures.data())
        XCTAssertEqual(HabitQuickTick.choices(projection: projection, language: .english).map(\.id), ["holds", "gym", "walk"])
        XCTAssertEqual(HabitQuickTick.choices(projection: projection, language: .czech).map(\.label), ["Výdrže", "Posilovna 2× týdně", "Ranní procházka"])
        XCTAssertTrue(HabitQuickTick.choices(projection: nil, language: .english).isEmpty)

        // 2030-10-23 12:00 in Prague.
        let noon = try XCTUnwrap(ISO8601DateFormatter().date(from: "2030-10-23T10:00:00Z"))
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        XCTAssertEqual(
            HabitQuickTick.tick(habitID: "walk", projection: projection, language: .english, now: noon, deviceTimeZone: utc),
            .tick(HabitTickPayload(date: today, habitId: "walk", done: true), label: "Morning walk")
        )
        // 01:30 in Prague is still the previous training day (boundary 3).
        let night = try XCTUnwrap(ISO8601DateFormatter().date(from: "2030-10-23T23:30:00Z"))
        XCTAssertEqual(
            HabitQuickTick.tick(habitID: "walk", projection: projection, language: .english, now: night, deviceTimeZone: utc),
            .tick(HabitTickPayload(date: today, habitId: "walk", done: true), label: "Morning walk")
        )
        XCTAssertEqual(
            HabitQuickTick.tick(habitID: "gym", projection: projection, language: .english, now: noon, deviceTimeZone: utc),
            .notPlannedToday(label: "Gym twice a week")
        )
        XCTAssertEqual(HabitQuickTick.tick(habitID: "nope", projection: projection, language: .english, now: noon, deviceTimeZone: utc), .unknownHabit)
        XCTAssertEqual(HabitQuickTick.tick(habitID: "walk", projection: nil, language: .english, now: noon, deviceTimeZone: utc), .unknownHabit)
    }
}
