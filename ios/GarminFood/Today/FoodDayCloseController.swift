// FoodDayCloseController.swift
//
// improve-food-day-flow (A2): the closed days as the screens read them -- a
// thin `@MainActor @Observable` holder over FoodLogCore's
// `FoodDayCloseStore` (the per-day local file). Every rule lives in
// FoodLogCore and is tested there (`FoodDayCloseRules`,
// `CompleteDaysStreak`); this only keeps a copy of the records in memory so
// the Today card, the evening reminder and the habit tick can read them
// without awaiting a file, and reloads that copy after each write.
//
// Local only: nothing here talks to Garmin or the vault, so both experiences
// and standalone mode have it. What closing a day ALSO does in the training
// experience (the `food-log` habit tick, the reminder's wording) is decided
// by AppEnvironment+FoodDayFlow, never here.
//
// Owned by AppEnvironment (`environment.foodDayClose`); the one store
// instance comes from AppServices. Read by FoodDayCloseCard (through
// TodayView) and TrainingModel's reminder replan.

import Foundation
import Observation
import FoodLogCore

@MainActor
@Observable
final class FoodDayCloseController {
    @ObservationIgnored private let store: FoodDayCloseStore

    /// Every closed day, by its `yyyy-MM-dd` key.
    private(set) var closes: [String: FoodDayClose] = [:]
    /// A close or an undo that could not be saved, for an alert.
    var errorMessage: String?

    init(store: FoodDayCloseStore) {
        self.store = store
    }

    /// Re-reads the file (launch, foreground, after each write).
    func reload() async {
        let all = await store.all()
        closes = Dictionary(all.map { ($0.day, $0) }, uniquingKeysWith: { _, last in last })
    }

    var closedDays: Set<String> {
        Set(closes.keys)
    }

    /// What the card shows for `day`, given how many entries it has.
    func state(day: String, entryCount: Int, today: String = NutritionDate.todayString()) -> FoodDayCloseRules.State {
        FoodDayCloseRules.state(day: day, today: today, entryCount: entryCount, record: closes[day])
    }

    /// Closed days in a row, up to today (or yesterday while today is open).
    func streak(today: String = NutritionDate.todayString()) -> Int {
        CompleteDaysStreak.length(closedDays: closedDays, today: today)
    }

    /// Closes `day`. `true` when it was closed by this call (a day that was
    /// already closed changes nothing).
    func close(day: String, entryCount: Int, now: Date = Date()) async throws -> Bool {
        let wasClosed = closes[day] != nil
        try await store.close(day: day, today: NutritionDate.todayString(now: now), entryCount: entryCount, now: now)
        await reload()
        return !wasClosed
    }

    /// Undo. `true` when the day was closed.
    func reopen(day: String) async throws -> Bool {
        let reopened = try await store.reopen(day: day)
        await reload()
        return reopened
    }

    /// An entry of `day` was added, changed or removed through the app: a
    /// closed day is marked "Edited after closing". Best effort -- a failed
    /// write only loses the mark, never the entry -- and nothing happens
    /// for a day that is not closed.
    func markEdited(day: String, now: Date = Date()) async {
        guard closes[day] != nil, closes[day]?.editedAt == nil else { return }
        do {
            if try await store.markEdited(day: day, now: now) {
                await reload()
            }
        } catch {
            // The day stays closed without the mark; nothing to show.
        }
    }
}
