## Why

Four things in the day-to-day food flow get in the owner's way:

- **Past days are slow to fill in.** The "Log again" and "Log a meal"
  shelves only show on today's date. Catching up yesterday means going
  through search for foods that are one tap away on today.
- **A day never ends.** Nothing says "that is everything I ate". The streak
  counts a day with one entry the same as a fully logged day, so neither the
  owner nor the training plan can tell a complete log from a partial one.
- **A carb-load day looks like any other day.** The plan marks the days
  before a race as carb-load days with a gram target, but the food screen
  does not say which race it is for, and the "Carb Loader" and "Race Day
  Fuel" badges only know the manual `race` day-note tag.
- **Deleting a synced entry needs the network.** Every other change to the
  log (add, edit, move, duplicate) is saved on the phone first and delivered
  later. Delete is a direct Garmin call: offline it fails with an alert and
  the entry stays.

## What Changes

- **A3 — quick logging on any day shown.** "Log again" and "Log a meal" show
  on past days too and log into the day being viewed. In the training
  experience they also show on a future day (the day switcher already
  reaches it). Food-first cannot reach a future day and is otherwise
  unchanged.
- **A2 — "That's everything today".**
  - A button under the last meal card closes the day's food log. It is
    stored on the phone per day, can be undone, and needs at least one entry.
  - A closed day stays closed when an entry is later added, changed or
    removed. It then says "Edited after closing".
  - A "complete days" streak counts consecutive closed days. It sits beside
    the existing one-entry streak, which is unchanged.
  - In the training experience the evening habits reminder also mentions the
    food log while the day is not closed.
  - In the training experience, when the plan's habit ladder has a habit
    with id `food-log` and the plan expects it that day, closing the day
    records `habit.tick { date, habitId: "food-log", done: true }` through
    the existing recorder. Undoing records `done: false`.
  - Food-first gets only the button and the local streak.
- **C3 — carb-load days drive the food screen.**
  - On a plan day with `fuel.kind == "carb-load"` the carb target is
    `fuel.carbsG`, else `carbsGPerKg` × weight (a `{ min, max }` band × weight
    when the plan gives one).
  - The fuel card says "Carb-load day for <race name>" and judges a single
    target as "Below target" or "Target reached".
  - In the training experience "Race Day Fuel" also counts the plan's race
    days, and "Carb Loader" is judged on the plan's carb-load days for that
    race. Without them the day-note `race` tag works as it does today.
- **E2 — deleting a synced entry works offline.**
  - The delete is queued on the phone (persisted, retried, tied to the
    Garmin account like every queued entry) and delivered later.
  - The entry shows "Deleting…" with its share taken off the totals, then
    disappears once Garmin confirms. A `404` means it is already gone.
  - A delete that gives up shows "Couldn't delete" on the row and in the
    sync queue, with Retry and "Keep entry".

## Capabilities

### New Capabilities

- `food-day-flow` — quick logging on the day shown, closing a day, the
  complete-days streak, the reminder mention and the `food-log` habit tick.
- `carb-load-fuel` — the carb-load day's target and title, and the race
  badges read from the plan.
- `food-log-delete-sync` — durable, retried, account-scoped deletes of
  synced food entries.

### Modified Capabilities

(none — the one-entry streak, the food-first summary and the edit flow are
unchanged)

## Non-goals

- Changing the vault, the event envelope or the contract fixtures. The
  `food-log` habit is defined by the vault's ladder; this change only ticks
  it. `HubEvent` is owned by `add-training-checkins` and is not edited here.
  Tests use synthetic inline projections.
- New training Today cards or changes to the Habits card. Owned by the
  training Today work running in parallel (`polish-training-today` and its
  follow-ups).
- XP, badges or moments for closing a day. Owned by a later gamification
  change; `add-gamification-signals` can read the store when it wants to.
- Planning screens for a carb load (the race screen already lists the days,
  `add-season-phase-race-screens`) and in-session fuelling.
- Offline deletes of weigh-ins and drinks. They are already queued
  (`sync-weight-hydration-with-garmin`).
- A new Garmin route. The delete route is the one the app already calls
  (`DELETE /nutrition-service/food/logs/{date}`).

## Impact

Re-grounded on `main` at `9654da4` (after #124, #127 and #128); every name
below was checked against the code.

- GarminKit: new `FoodLogDeletionQueue.swift` (the queue's record, its file
  and the drain); `Outbox` owns the queue and gains `queueDeletion`,
  `allDeletions`, `retryDeletion`, `cancelDeletion`, `drainDeletions` and
  `pruneConfirmedDeletions`. A new per-process file
  `food-delete-outbox-<process>.json` (with a store fixture); the outbox
  file is unchanged.
- FoodLogCore: new `FoodDayClose.swift` (the per-day store
  `food-day-closes.json`, the close rules and the complete-days streak) and
  `QuickLogShelfPolicy.swift`; `LogEntryCoordinator.deleteCommitted` queues
  instead of calling Garmin (its `garminLog` parameter and
  `CommittedDeleteError` go away); `MealDashboard` overlays queued deletes
  (`MealEntry.deletion`); `OutboxBacklog` and `BackgroundOutboxDelivery`
  cover them; `FuelDayTarget` and `FuelDaySummary` gain the race name and
  the single-target judgement; `StoreCatalog` gains two entries.
- TrainingCore: `DayFuelTargets` (a `{ min, max }` band on a carb-load day,
  the race id), new `FoodLogHabit.swift`, `TrainingReminderPlanner` (the
  food-log mention), one new string. **Not** `TrainingRewardFacts`: since
  #124 the plan's race days and carb-load days are already facts in
  `TrainingPlanFacts` (`races`, `PlanDayFact.carbLoadRaceId`).
- Gamification: `TrainingPlanSignals.Day` gains `carbLoadRaceId` (**not**
  `TrainingSignals`, for the same reason); `SportRules` and
  `SportAndBodyFeature` (plan-aware race rules, read from
  `FeatureContext.trainingPlan`).
- App: `TodayView`, `DayLogLoader`, `EntryEditing`, `FuelSummaryCard`,
  `SyncQueueView`, `AppEnvironment`, `AppServices`, `TrainingModel`,
  `TrainingNutritionBridge`, `TrainingPlanSignalsBridge`; new
  `FoodDayCloseController.swift`, `FoodDayCloseCard.swift`,
  `AppEnvironment+FoodDayFlow.swift`. New EN + CS strings.
- `HubEvent.swift`, the mirrored contract fixtures and their golden tests
  are not touched: `habit.tick` already exists, and the tick goes through
  `TrainingModel.setHabit`, the path Today's Habits card uses.
- **Depends on**: `add-app-shell-and-meal-dashboard`,
  `improve-log-food-shelves`, `add-log-entry-editing`,
  `add-winter-arc-nutrition-and-rewards` (fuel decoding, #119),
  `add-training-checkins` (the recorder), `add-interactive-habits` (habit
  days and the back-fill window), `add-training-gamification-and-150-levels`
  (the plan's facts, #124), `fix-review-findings-2026-09` (account scope,
  #116).
- **Unblocks**: a vault-side `food-log` habit that is ticked by closing the
  day; rewards for complete days.
