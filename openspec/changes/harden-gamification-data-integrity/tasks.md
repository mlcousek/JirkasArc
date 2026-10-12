## 1. Model and lifecycle

- [x] 1.1 Add a stable local identity to each usage event and carry it from
  outbox creation through confirmation. (`UsageEvent.entryId`/`garminLogId`;
  every Garmin and standalone record call passes its entry id; Reconciliation
  links Garmin's logId -- design D1.)
- [x] 1.2 Add targeted usage-history removal for delivered-entry deletion and
  queued-entry cancellation; never remove an unrelated identical food.
  (`UsageHistoryStore.remove`/`reassign`; `deletePending`, `deleteCommitted`,
  standalone `deleteStored`, `edit` -- design D2, D3.)
- [x] 1.3 Pass the selected nutrition day and durable-entry count into the
  gamification confirmation boundary. (`handleLogConfirmed(nutritionDay:
  entries:)` -- design D5.)

## 2. Lifetime accounting

- [x] 2.1 Attribute calorie totals and daily maxima to the selected nutrition
  day.
- [x] 2.2 Record one lifetime log per durable food entry in a preset.
- [x] 2.3 Replace adjacent-call-only goal-day tracking with per-date
  idempotency and define the persistence/migration bounds. (`countedGoalDays`
  -- design D4.)

## 3. Regression coverage

- [x] 3.1 Add persistence/reload tests for the lifetime ledger.
- [x] 3.2 Add red-to-green package tests for out-of-order goal statuses.
  (`LifetimeStatsStoreTests.testAnOlderDayRefetchedAfterANewerOneIsNotCountedAgain`,
  `testCountedGoalDaysSurviveAReload`, `testALedgerFromBeforeTheDaySetStillGuardsItsLastCountedDay`)
- [x] 3.3 Add usage-history identity/removal tests. (`UsageEventIdentityTests`)
- [x] 3.4 Add app integration tests for delete/cancel, backdated entries,
  and meal presets. **At package level, not app level (design D6):** the app
  target has no test bundle. Delete/cancel and presets in
  `UsageEventIdentityTests`; backdated and preset counts in
  `LifetimeStatsStoreTests.testABackdatedLogAddsToTheSelectedDayNotTheTapDay`,
  `testAPresetCountsOneLifetimeLogPerIngredient`.
- [x] 3.5 Add an achievement-permanence regression case to the delete flow.
  (`AchievementTests.testABadgeEarnedByADeletedFoodStaysUnlocked`)

## 4. Verification

- [ ] 4.1 Run `swift test` for `FoodLogCore` and `Gamification` (CI).
- [ ] 4.2 Run the app-target integration suite on iOS Simulator. (No app test
  bundle exists; the CI app build is the check -- design D6.)
- [ ] 4.3 Perform the manual lifecycle scenarios from `design.md` (owner, on
  the phone).
