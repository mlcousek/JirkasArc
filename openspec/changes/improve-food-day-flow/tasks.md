Every task ends with CI green: `swift test` for GarminKit, FoodLogCore,
Gamification and TrainingCore, the design-token lint, the app and widget
`xcodebuild`, and the `localization` job. Every new `.swift` file starts
with a header comment saying why it exists and what depends on it. All new
user-facing text is in English and Czech. **Fixtures are synthetic**: no
token, account id, real weight, health history or vault content in code,
tests, fixtures or docs; race names in tests are invented. Branch
`mlcousek/food-day-flow` on `main`. `HubEvent.swift`, the mirrored
contract fixtures and their golden tests are not touched, and no badge is
added (`BadgeArtCatalog` untouched). No task writes to Garmin through a
route the app did not already call. Relative size: S / M / L.

A box is ticked when the code was written and read back against its call
sites and tests; nothing here was compiled locally (no Swift toolchain),
so 9.2 and 9.3 stay open until CI and the phone have said so.

## 1. Re-ground the proposal (S)

- [x] 1.1 Check every file and symbol of the proposal's Impact section against `main` after #124, #127 and #128; correct the section (the plan's race days and carb-load days are already facts in `TrainingPlanFacts` / `TrainingPlanSignals`).
- [x] 1.2 `design.md`, the three specs and this file; `openspec validate improve-food-day-flow --strict`.

## 2. E2 -- the delete queue in GarminKit (L)

- [ ] 2.1 `FoodLogDeletionQueue.swift`: `FoodLogDeletion` (every later field optional), `FoodLogDeletionStore` (one file per process, `food-delete-outbox-<process>.json`, atomic, never over a file it could not read, an in-flight claim) and `FoodLogDeletionDrainResult`.
- [ ] 2.2 `Outbox`: owns the second store; `queueDeletion` (stamped with the account, one record per entry), `allDeletions`, `retryDeletion`, `cancelDeletion` (refused in flight and once delivered), `pruneConfirmedDeletions`; `assignUnscopedEntries` covers both files.
- [ ] 2.3 `Outbox.drainDeletions`: 2xx and 404 delivered, 429 stops with `Retry-After`, auth and no connection stop without an attempt, another 4xx gives up at once, anything else backs off and gives up after `maxAttempts`; another account's delete is held.
- [ ] 2.4 Store fixture `food-delete-outbox-app.json` and its test; the new interpolated prefix in `StoreFixtureTests`.

## 3. E2 -- FoodLogCore and the app (L)

- [ ] 3.1 `LogEntryCoordinator.deleteCommitted` queues (local write only); `garminLog` and `CommittedDeleteError` removed; `AppServices` updated.
- [ ] 3.2 `MealDashboard.build(deletions:)`: `MealEntry.deletion`, a waiting delete's share off the totals, a confirmed one hidden, one that gave up counted; `canRelog` false while a delete is queued.
- [ ] 3.3 `OutboxBacklog` and `BackgroundOutboxDelivery` cover the delete queue (creates, the re-read, then deletes).
- [ ] 3.4 `StoreCatalog`: `garminkit.food-delete-outbox` (device only, not in backups).
- [ ] 3.5 App: `DayLogLoader` (deletes in the rebuild, prune after a read, no wait on delete), `AppEnvironment` (drain order, the queue's state, retry and "Keep entry"), `MealEntryRow` and `EntryEditing` ("Deleting…", "Couldn't delete", Retry, "Keep entry"), `SyncQueueView` (the deletes section).

## 4. A3 -- quick logging on the day shown (S)

- [ ] 4.1 `QuickLogShelfPolicy` in FoodLogCore.
- [ ] 4.2 `TodayView.availability` uses it for "Log again" and "Log a meal"; the layout editor's two explanations reworded.

## 5. A2 -- closing a day (L)

- [ ] 5.1 `FoodDayClose.swift`: `FoodDayClose`, `FoodDayCloseStore` (`food-day-closes.json`), `FoodDayCloseRules` (can close, state, edited after closing) and `CompleteDaysStreak`.
- [ ] 5.2 `StoreCatalog` entry `foodlog.food-day-closes` (in backups) and the store fixture with its test.
- [ ] 5.3 TrainingCore: `FoodLogHabit.tick`, `TrainingReminderPlanner.plan(closedFoodDays:)`, the string `reminderHabitsBodyFoodLog` in both tables.
- [ ] 5.4 App: `FoodDayCloseController`, `FoodDayCloseCard` under the meal cards, `AppEnvironment+FoodDayFlow` (close, undo, mark edited from every in-app change, the habit tick through `TrainingModel.setHabit`), `TrainingModel` passes the closed days to the planner.

## 6. C3 -- carb-load days (M)

- [ ] 6.1 `DayFuelTargets`: the `{ min, max }` band on a carb-load day, `carbLoadRaceId`.
- [ ] 6.2 `FuelDayTarget.raceName`, `FuelDaySummary.raceName` and `.targetStatus`.
- [ ] 6.3 `TrainingNutritionBridge` passes the race's name; `FuelSummaryCard` title and "Below target" / "Target reached".
- [ ] 6.4 `TrainingPlanSignals.Day.carbLoadRaceId` (copied by `TrainingPlanSignalsBridge`); `SportRules.isRaceDay(_:today:plan:)` and `carbLoadedRaceDays(in:calendar:plan:)`; `SportAndBodyFeature` passes `context.trainingPlan`.

## 7. Strings (S)

- [ ] 7.1 App strings in `Localizable.xcstrings` (English and Czech, the complete-days count with Czech one / few / other); the TrainingCore string in both `.lproj` tables.

## 8. Tests (L)

- [ ] 8.1 GarminKit `FoodLogDeletionQueueTests`: the record's round trip and an older file, one record per entry, 2xx and 404, offline, 429, auth, a refused delete, five server errors, retry, "Keep entry" (also in flight and once delivered), account scope and sign-out, pruning.
- [ ] 8.2 FoodLogCore: `MealDashboardTests` (waiting, confirmed, gave up), `FoodLoggingTests` and `ModeRoutingTests` (a delete is queued, standalone queues nothing), `BackgroundOutboxDeliveryTests` (a delete-only queue, backlog counts), `QuickLogShelfPolicyTests`, `FoodDayCloseTests` (store, rules, streak with gaps and edited days), `FuelDayTests` additions, `StoreCatalogTests` lookups.
- [ ] 8.3 TrainingCore: `DayFuelTargetsTests` additions (grams, number, band, no weight, race id), `FoodLogHabitTests`, the reminder text in `DailyCheckInTests`.
- [ ] 8.4 Gamification: `SportRulesTests` additions (plan race days, plan carb-load days, the tag fallback).

## 9. Verification

- [ ] 9.1 `openspec validate improve-food-day-flow --strict`, `node tools/check-localizations.mjs --scan`, `sh tools/lint-design-tokens.sh`, the `TrainingKey` table check; every new or changed Swift file read back for compile errors.
- [ ] 9.2 CI green on the PR (Swift compiles only there).
- [ ] 9.3 On the phone: delete a synced entry in flight mode ("Deleting…", totals drop), come back online (the row goes, Garmin Connect agrees); "Log again" on yesterday; close today, add a food ("Edited after closing"), undo; the complete-days count over three days; with the vault connection on and a `food-log` habit in the ladder, the tick after closing and the evening reminder's wording; a carb-load day's title and target.
