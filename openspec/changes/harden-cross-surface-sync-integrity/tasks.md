## 0. Verdict (2026-10-09)

Every finding in this change (F1-F18, design.md) was re-raised the same day
as `fix-review-findings-2026-09` (16 findings) and `fix-review-findings-2026-09-b`
(2 findings), checked against the code there, and either fixed or shown not
real, with evidence and tests (PRs #116 and #117, merged 2026-09-30; both
changes archived 2026-10-07). This change's findings were written earlier the
same morning (cf3f893, 3ca1746) and never updated, so nothing below is
re-implemented. Re-checked against `main` at 43b1db0: every type and test
named below exists. Mapping: F1=1, F2=3, F3=2, F4=4, F5=7, F6=5, F7=6, F8=8,
F9=9, F10=10, F11=11, F12=14, F13=12, F14=13, F15=15, F16=16 of
fix-review-findings-2026-09; F17=1, F18=2 of fix-review-findings-2026-09-b.

## 1. Consistent food post-commit behavior

- [x] 1.1 **SUPERSEDED (F1 = fix-review-findings-2026-09 #1, real, fixed):** the shared post-commit path is `ConfirmedLogRelay` + `QuickPickCommit` (FoodLogCore); `AppEnvironment` attaches `GamificationEngine.handleLogConfirmed` once at launch. No separate pipeline type: the confirm screens, `duplicateEntry` and `copyMeal` already call `handleLogConfirmed` + `logConfirmed` directly. Extract a shared app-layer post-commit pipeline for food logging.
- [x] 1.2 **SUPERSEDED (F1):** the four quick-pick Controls, "Log usual food" and "Log <food>" report through the relay (`QuickPickControlAction.performLog`, `LogNamedFoodIntent`). Route SwiftUI, Siri, and Control quick-pick confirmation through it.
- [x] 1.3 **SUPERSEDED (F1):** `ConfirmedLogRelayTests` (awarded exactly once while running, held then awarded once before attach, same log twice awarded once, failed commit awards nothing). Add an exactly-once gamification integration test for Quick Pick.

## 2. Durable background delivery

- [x] 2.1 **SUPERSEDED (F2 = #3, real in part, fixed):** `OutboxBacklog.needsDelivery` reads all three outboxes; `weightLogged`/`hydrationLogged` refresh the queue count. Expose pending work across food, weight, and hydration queues.
- [x] 2.2 **SUPERSEDED (F2):** `BackgroundOutboxDelivery`, used by `BackgroundRefresh` and `didEnterBackground`. Drain all supported queues in the registered background task.
- [x] 2.3 **SUPERSEDED (F2):** `BackgroundOutboxDeliveryTests.testAWeightOnlyQueueIsDeliveredInTheBackground`, `testAWaterOnlyQueueIsDeliveredInTheBackground`, `testAWeightOrWaterOnlyQueueKeepsTheRefreshScheduledWhileGarminIsUnreachable`. Add background-worker tests for weight-only and hydration-only work.

## 3. Custom-food create recovery

- [x] 3.1 **SUPERSEDED (F3 = #2, real, fixed):** `CustomFoodCreation` (GarminKit): any 2xx is a create; an unreadable body is `.createdDetailsPending`. Classify post-2xx response decoding failure as ambiguous success.
- [x] 3.2 **SUPERSEDED (F3):** `CustomFoodCreateGate` (FoodLogCore) never offers a second create after a 2xx; the create screen uses it. Add a reconcile/re-search recovery path before another create.
- [x] 3.3 **SUPERSEDED (F3):** `CustomFoodCreationTests` (201 with an unexpected body, 200 with an empty body, non-2xx still retryable), `CustomFoodCreateGateTests`. Add transport and UI-state regression tests for an unreadable 2xx body.

## 4. Weight and hydration atomicity

- [x] 4.1 **SUPERSEDED (F4 = #4, real, fixed):** failure injection in `LocalFirstHealthLoggingTests`. Add failure injection for local-history persistence.
- [x] 4.2 **SUPERSEDED (F4):** the order is reversed instead of compensated: the outbox id is chosen up front, the local record is saved first, then enqueued; a failed save queues nothing and the stores roll back in memory. Compensate or retain a durable local pending record when local persistence fails after queueing.
- [x] 4.3 **SUPERSEDED (F4):** `LocalFirstHealthLoggingTests.testAFailedLocalWeightSaveQueuesNothingForGarmin`, `testAFailedLocalDrinkSaveQueuesNothingForGarmin`, `testASuccessfulSaveStillLinksTheLocalRecordToItsQueuedEntry`. Test successful compensation and explicit compensation-failure recovery.

## 5. Food lifecycle integrity

- [x] 5.1 **SUPERSEDED (F5 = #7, not real):** every quick-pick card passes its amount (`FoodCatalogView.selectQuickPick`, `TodayView.logAgain`, `LogQuantity.initial(remembered:)`); the Control/Siri path carries `entry.numberOfUnits` (`QuickPickResolutionTests.testACatalogFoodResolvesWithItsExactServingAndRememberedAmount`). Carry a Quick Pick's retained quantity into confirmation and add a UI-input mapping regression test.
- [x] 5.2 **SUPERSEDED (F6 = #5, not real):** a claimed food entry can't be cancelled (`OutboxEditError.entryInFlight` -> `LogEntryEditError.stillSyncing`); weight and water keep a tombstone and send the compensating delete once accepted (`OutboxTests.testAnEntryBeingSentCannotBeEditedUnderneathTheDrain`, `WeightSyncTests.testDeletingAWeighInWhileItsPostIsInFlightDeletesItFromGarminOnceAccepted`). Represent deletion requested during an in-flight delivery as a compensating remote-delete operation; add a gated-delivery race test.
- [x] 5.3 **SUPERSEDED (F7 = #6, not real):** only a provable retry copy (same `createdAt`, 2 ms) is ever deleted (`Reconciliation.provableRetryCopies`; `ReconciliationTests.testASecondIdenticalLogWithinTheClockToleranceIsNeverDeleted`). Stop destructive duplicate cleanup without a reliable ownership identifier; add a later independent-Garmin-entry regression test.
- [x] 5.4 **SUPERSEDED (F8 = #8, real, fixed):** later background passes reconcile every `.sent` food entry and an unreconciled one keeps a refresh scheduled (`BackgroundOutboxDeliveryTests.testAnAcceptedFoodEntryWhoseReReadFailedIsReconciledByALaterBackgroundPass`). Reconcile previously sent entries and retain background scheduling after a reconciliation read failure.

## 6. Account and notification lifecycle

- [x] 6.1 **SUPERSEDED (F9 = #9, real, fixed):** `GarminAccountKey` stamps every outbox entry; drains and Reconciliation only send to the matching account; another account's entries are held, never sent or dropped; sign-out ties unstamped entries to the outgoing account. Not done, by decision (fix-review-findings-2026-09 D5): purging other local data on an account change. Bind retained queues and account-scoped local data to a stable Garmin identity; quarantine or purge it safely on account change.
- [x] 6.2 **SUPERSEDED (F9):** `DeliverySafetyTests` (food and weight/water held for their own account, sign-out ties unstamped entries, the key trusted only for its token). Add same-account reconnect and different-account switch tests.
- [x] 6.3 **SUPERSEDED (F10 = #10, real, fixed):** granting the prompt from undecided re-syncs once (`NotificationWindowTests.testGrantingPermissionTriggersAResyncOnlyOnTheTransition`). Re-run notification scheduling after first authorization is granted.
- [x] 6.4 **SUPERSEDED (F11 = #11, real, fixed):** `NotificationPlanning.planWindow` plans 7 days; `TrainingReminderPlanner.plan(days: 7)`. Schedule/reconcile a future reminder horizon that survives midnight without foregrounding.
- [x] 6.5 **SUPERSEDED (F10, F11):** `NotificationWindowTests`, `CheckInBuilderTests.testAWiderWindowPlansTheFollowingDaysToo`. Add authorization-transition and date-rollover scheduler tests.

## 7. Profile, search, and delivered-data consistency

- [x] 7.1 **SUPERSEDED (F12 = #14, not real):** `ProfileView.headerName` prefers the local name, then `fullName`, then `displayName`. Prefer validated user-facing profile names over opaque display IDs.
- [x] 7.2 **SUPERSEDED (F13 = #12, not real):** the only UI delete path queues a Garmin delete (by sample, or by match for a delivered unmatched weigh-in) (`WeightLogCoordinatorTests.testDeletingADeliveredButUnmatchedWeighInDeletesItFromGarminByMatch`). Add remote-aware delivered weigh-in deletion with visible retry recovery.
- [x] 7.3 **SUPERSEDED (F14 = #13, not real):** the search runs in `.task(id:)`, `FoodSearchModel.run` checks cancellation before applying each snapshot with no suspension in between, and the engine stops emitting once cancelled (`FoodSearchEngineTests.testStoppingTheStreamCancelsTheDebouncedRemoteSearch`). Add a request-generation guard around catalog and Open Food Facts result application.
- [x] 7.4 **SUPERSEDED (F12-F14):** covered by the tests named in 7.1-7.3. Add regression tests for profile-name selection, delivered weigh-in deletion, and superseded search responses.

## 8. Durable-store recovery

- [x] 8.1 **SUPERSEDED (F15 = #15, not real):** `PersistedJSON.load` tells missing (empty) from unreadable (left in place; every write refused by `ensureSafeToWrite` until a read succeeds) from undecodable (moved aside) (`PersistedJSONTests.testUnreadableOutboxRefusesToSaveThenRecoversOnceReadable`). Distinguish missing persisted files from unreadable existing files; retry safely or reject writes while data is unavailable.
- [x] 8.2 **SUPERSEDED (F16 = #16, real, fixed):** each outbox saves a send marker before sending and doesn't send if that fails; a reload with the marker never re-sends blindly (food -> Reconciliation, weigh-in -> looked up first, drink -> failed with a note). Make remote acknowledgement state durable before reporting delivery, with an explicit ambiguous-delivery recovery state if persistence fails.
- [x] 8.3 **SUPERSEDED (F15, F16):** `DeliverySafetyTests` (accepted-but-unrecorded food, weigh-in and drink after a restart; a send that can't be recorded isn't made), `PersistedJSONTests`. Add restart tests for transient read failure and post-acknowledgement write failure across food, weight, and hydration queues.

## 9. Data-contract correctness

- [x] 9.1 **SUPERSEDED (F17 = fix-review-findings-2026-09-b #1, real, fixed):** `GarminWireDate` (GarminKit) and `NutritionDate` are Gregorian with the local time zone; every write body, route date and key parser goes through them. Use Gregorian calendar rules for Garmin wire-date formatting and parsing while retaining the relevant local timezone.
- [x] 9.2 **SUPERSEDED (F18 = fix-review-findings-2026-09-b #2, real in part, fixed):** zero, negative and non-finite amounts were already refused before the outbox; the missing upper bound was added (`CustomFoodDraft.backingQuantityIsValid`, `MealPreset.backingQuantitiesAreValid`, `LogQuantityError.backingOutOfRange`; the coordinator refuses before enqueue). Reject zero, negative, and non-finite custom-food multiplier and resulting serving quantities at UI, domain, and outbox boundaries.
- [x] 9.3 **SUPERSEDED (F17, F18):** `GarminWireDateTests`, `NutritionDateTests.testTheDayIsGregorianOnABuddhistOrJapanesePhone`, `WeekKeyTests.testDayKeysStayGregorianOnABuddhistPhone`, `CustomFoodTests`, `LogEntryCoordinatorTests`. Add non-Gregorian-calendar and invalid-custom-quantity regressions.

## 10. Verification

- [x] 10.1 **SUPERSEDED:** the package suites run in CI on every push; this change adds no code. Run all Swift package suites.
- [x] 10.2 **SUPERSEDED:** this change adds no code. Run app-target integration tests on iOS Simulator.
- [ ] 10.3 Verify background delivery on a device with interrupted connectivity. (Carried by fix-review-findings-2026-09 3.4, the owner's device check.)
