// FoodLogHabit.swift
//
// improve-food-day-flow (A2, design D7): closing a day's food log ("That's
// everything today") is also the tick of one habit of the plan -- when the
// plan has such a habit. The habit is the vault's to define; the app only
// knows its id, `food-log`. A ladder without it changes nothing, and so
// does the food-first experience (it has no plan at all).
//
// This file only DECIDES whether a tick should be recorded; the app records
// it through `TrainingModel.setHabit`, the very call Today's Habits card
// makes, so the wire format (`habit.tick`, HubEvent.swift) is untouched.
// A tick is due only when ALL of these hold:
//   - the app may record ticks (`TrainingCapabilities.canTickHabits`: the
//     vault connection is on and has a device id) -- otherwise nothing is
//     sent and nothing is shown as an error;
//   - the ladder has a habit with id `food-log`, and it is one that takes
//     ticks (not measured by the vault from activities or the plan);
//   - the plan expects it on that day -- the same day lookup as every
//     Habits screen (`HabitTimeline.record`);
//   - the day is today or one of the 14 days before (`HabitBackfill`: the
//     vault refuses an older or a later day);
//   - the habit is not already in that state (the owner may have ticked it
//     by hand on the Habits card).
// Closing asks for `done: true`, undoing the close for `done: false`.
//
// Pure. Depended on by: the app's AppEnvironment+FoodDayFlow. Tests:
// FoodLogHabitTests.

import Foundation

public enum FoodLogHabit {
    /// The id the vault's ladder gives the habit closing the food log ticks.
    public static let habitID = "food-log"

    /// The tick to record when the food log of `date` was closed (`closed:
    /// true`) or re-opened (`false`); `nil` when nothing should be recorded.
    public static func tick(closed: Bool, on date: LocalDate, snapshot: TrainingSnapshot?, today: LocalDate) -> HabitTickPayload? {
        guard let snapshot,
              snapshot.capabilities.canTickHabits,
              let habit = snapshot.habits.habit(habitID),
              !HabitBackfill.isMeasured(habit),
              HabitBackfill.allows(date, today: today)
        else { return nil }
        // Expected by the Habits screens' own lookup, or listed on the day
        // itself (a day outside the written weeks is a skeleton, which the
        // reminders read the same way).
        let listed = snapshot.day(date)?.habitsExpected.contains(habitID) ?? false
        let record = HabitTimeline.record(for: habit, on: date, snapshot: snapshot, today: today)
        guard listed || record.expected > 0 else { return nil }
        guard snapshot.habitDone(habitID, on: date).done != closed else { return nil }
        return HabitTickPayload(date: date, habitId: habitID, done: closed)
    }
}
