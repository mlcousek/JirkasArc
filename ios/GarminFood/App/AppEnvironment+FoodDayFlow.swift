// AppEnvironment+FoodDayFlow.swift
//
// improve-food-day-flow (A2): what closing a day's food log does besides
// writing the record -- the parts that need more than one of the app's
// pieces, so they sit here and not in a view or in FoodDayCloseController:
//
//   - `closeFoodDay()` / `reopenFoodDay()`: the Today card's two actions on
//     the day being shown. Local and immediate; a failed write is shown.
//   - the `food-log` habit: in the training experience only, and only when
//     TrainingCore's `FoodLogHabit.tick` says so (the ladder has that id,
//     the plan expects it that day, the vault still accepts the day, the
//     connection can record), the same call Today's Habits card makes
//     (`TrainingModel.setHabit`) records `habit.tick`. Food-first, and a
//     phone without a working vault connection, record nothing and show no
//     error.
//   - the evening reminder: the closed days are handed to the training
//     reminder plan (`TrainingModel.closedFoodDaysProvider`), and every
//     close or undo re-plans, so the wording follows at once.
//   - `foodDayChanged(day:)`: called by AppEnvironment after every change
//     it makes to a day's entries; a closed day then says "Edited after
//     closing" and stays closed.
//
// Nothing here waits for the network, and nothing here knows a habit's
// meaning: the id is the vault's.
//
// Depends on: AppEnvironment, FoodDayCloseController, TrainingModel,
// TrainingCore (FoodLogHabit, LocalDate). Depended on by: AppEnvironment
// (init, the entry actions), TodayView (the close card).

import Foundation
import FoodLogCore
import AppearanceKit
import TrainingCore

extension AppEnvironment {
    /// Called once at the end of `init`.
    func wireFoodDayFlow() {
        // The evening habits reminder mentions a food log that is not
        // closed. `nil` outside the training experience: nothing is asked.
        training.closedFoodDaysProvider = { [weak self] in
            guard let self, self.experience == .training else { return nil }
            return Set(self.foodDayClose.closedDays.compactMap { LocalDate($0) })
        }
        Task { [weak self] in
            await self?.foodDayClose.reload()
        }
    }

    /// Entries of the day on screen, not counting one whose delete is
    /// waiting -- what "at least one entry" is judged by.
    var foodDayEntryCount: Int {
        var count = 0
        for section in dayLog.dashboard.sections {
            for entry in section.entries where !entry.isBeingDeleted {
                count += 1
            }
        }
        return count
    }

    /// "That's everything today" on the day being shown.
    func closeFoodDay() async {
        let day = dayLog.dateString
        do {
            guard try await foodDayClose.close(day: day, entryCount: foodDayEntryCount) else { return }
        } catch {
            foodDayClose.errorMessage = String(localized: "Couldn't save that on the phone. Try again.")
            Haptics.warning()
            return
        }
        Haptics.success()
        await recordFoodLogHabit(closed: true, day: day)
        await syncNotifications()
    }

    /// Undo of the close on the day being shown.
    func reopenFoodDay() async {
        let day = dayLog.dateString
        do {
            guard try await foodDayClose.reopen(day: day) else { return }
        } catch {
            foodDayClose.errorMessage = String(localized: "Couldn't save that on the phone. Try again.")
            Haptics.warning()
            return
        }
        await recordFoodLogHabit(closed: false, day: day)
        await syncNotifications()
    }

    /// An entry of `day` was added, changed or removed through the app.
    func foodDayChanged(day: String) async {
        await foodDayClose.markEdited(day: day)
    }

    /// The plan's `food-log` habit, when it has one and expects it on
    /// `day` (see the header). Training experience only.
    private func recordFoodLogHabit(closed: Bool, day: String) async {
        guard experience == .training,
              let date = LocalDate(day),
              let payload = FoodLogHabit.tick(closed: closed, on: date, snapshot: training.source.snapshot, today: training.today())
        else { return }
        await training.setHabit(payload.habitId, done: payload.done, date: payload.date)
    }
}
