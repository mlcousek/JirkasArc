## Context

The proposal was drafted about fifty commits before this change was
written. It was re-grounded on `main` at `9654da4` (2026-10-06), after
interactive habits (#123), training gamification with 150 levels (#124),
supplements, the September review fixes and gates, load and results (#128).
What was read, in the code and not in older documents:

- `GarminKit/Outbox.swift`, `WeightSync.swift`, `DeliverySafety.swift`,
  `ConnectivityFailure.swift`, `PersistedJSON.swift`: how a queue persists
  (one JSON file per process, atomic write, never over a file it could not
  read), retries (capped backoff with jitter, a 429 and an auth failure stop
  the cycle, being offline is not an attempt), scopes entries to the Garmin
  account (`AccountScope`, stamped at enqueue, checked before each send) and
  guards an entry that is in flight (`claim`).
- `FoodLogCore`: `LogEntryCoordinator.deleteCommitted` is the one food-log
  write that calls Garmin directly; `DayLogLoader.delete` then re-reads the
  day. `MealDashboard.build` already hides the old entry of a queued edit
  and takes its share off Garmin's totals.
- `TrainingCore`: `DayFuelTargets.resolve` already turns a carb-load day
  into a one-point band (`carbsG`, else `carbsGPerKg` x weight), but ignores
  a `{ min, max }` band on such a day; `DayFuel.raceId` is decoded and never
  shown. `TrainingPlanFacts` (since #124) already carries the season's
  races with their dates and each day's `isCarbLoad` and `carbLoadRaceId`,
  and the app copies them into Gamification's `TrainingPlanSignals` --
  except `carbLoadRaceId`, which the bridge drops.
- `Gamification/SportRules.swift`: "Race Day Fuel" and "Carb Loader" read
  only the day-note `race` tag.
- `HabitTimeline` / `HabitBackfill`: a habit day is looked up with
  `HabitTimeline.record`, and the vault accepts a tick for today and the 14
  days before.
- The delete route: `DELETE /nutrition-service/food/logs/{date}` with
  `{ "logIds": [...] }`, recorded in `docs/garmin-routes.json`, last
  verified 2026-09-16 as "modelled on a live-tested client, not yet
  exercised by this project". This change adds no route and changes
  neither the path nor the body.

No Swift toolchain on the owner's machine: nothing here was compiled
locally. Correctness rests on the package tests in CI.

## Goals / Non-Goals

**Goals:** a delete of a synced entry that survives being offline and is
never silent when it gives up; the quick-log shelves on every day the
screen can show; a way to say "this day is complete", kept on the phone,
with its own streak; a carb-load day that names its race and a target the
food screen judges; race badges that follow the plan.

**Non-Goals:** rewards for closing a day; a new training Today card; a new
event type or any change to `HubEvent.swift`; a new Garmin route; offline
deletes of weigh-ins and drinks (already queued).

## Decisions

### D1. Deletes get their own queue file, owned by the food `Outbox`

A delete is not an `OutboxEntry`: that record is a food to create (meal,
food id, serving, amount) and its file is read by every build on the
phone. Adding an "operation" to it would make a delete look like a create
to an older build. So the delete has its own record, `FoodLogDeletion`
(`id`, `date`, `logId`, `state`, `attemptCount`, `lastError`, `createdAt`,
`nextAttemptAt`, `accountKey`), in its own file,
`food-delete-outbox-<process>.json`, next to the outbox file. `Outbox`
owns both stores, so one actor stamps the account, signs entries over on
sign-out (`assignUnscopedEntries` covers both files) and answers the sync
queue.

The drain (`Outbox.drainDeletions`) follows the food drain rule for rule:

| Garmin's answer | What happens |
|---|---|
| 2xx | delivered |
| 404 | delivered -- the entry is already gone |
| 429 | attempt counted, `Retry-After` honoured, the cycle stops |
| auth failure | the cycle stops, no attempt counted |
| no connection | the cycle stops, no attempt counted |
| another 4xx (not 408) | gives up at once: retrying cannot fix it |
| anything else | backoff; gives up after `maxAttempts` (5) |

A delete of another account is held, never sent. There is no send marker
(`sendStartedAt`): repeating a delete is harmless, the second one answers
404.

A delivered delete is kept as `.sent` until the day has been read again
without that entry (`pruneConfirmedDeletions`), or for a week at most. Without
that, the row would come back between Garmin's answer and the next read of
the day.

**Garmin's answer is checked, not trusted** (review, 2026-10-06). The route
has never been exercised on a device and a 404 counts as "already gone", so
a wrong route, date or id would make every delete look delivered while the
entry stays in Garmin -- hidden on the phone. The same re-read that drops a
confirmed delete therefore checks it: when the day still lists the entry
more than `Outbox.deletionConfirmationGrace` (5 minutes) after Garmin's
answer, the delete goes back to `failed` with an error that says the day
still lists it. The row reappears as "Couldn't delete", counts again and
offers Retry and "Keep entry". Inside the grace nothing changes: a read
that started before the delete landed is normal.

*Alternative:* an `operation` field on `OutboxEntry`, as the weight queue
did. Refused: the weight queue added it before anything else read the file;
the food outbox is read by Reconciliation, the dashboard, the mode switch
and the sync queue, each of which would need to learn to skip a delete.

*Fallback if the route breaks:* the delete gives up after five attempts (or
at once on a 4xx), the row says "Couldn't delete" and the entry is counted
again. Nothing is lost on the phone, and the entry can be deleted in Garmin
Connect.

### D2. Creates first, then the re-read, then deletes

`AppEnvironment.drainAndReconcile` and `BackgroundOutboxDelivery.run` send
queued creates, reconcile the accepted ones against Garmin's log, and only
then send deletes. A delete sent before an accepted create was confirmed
could make that create look "missing" to Reconciliation, which would send
it again.

### D3. What the day shows

`MealDashboard.build` takes the queued deletes of the day:

- **waiting** (`pending`): the row stays, marked `MealEntry.deletion ==
  .deleting`, and its calories and macros come off the meal and the day;
- **confirmed** (`sent`): the row is hidden and its share stays off, until
  the day is read again;
- **gave up** (`failed`): the row is marked `.failed` and its share counts
  again -- the entry really is still in Garmin.

A row that is being deleted cannot be edited, moved or duplicated
(`canRelog` is false). `MealEntry.Status` keeps its three cases, so no
existing `switch` changes.

Two places read Garmin's raw day instead of the built dashboard, and get
the same answer through `MealDashboard.removedLogIds` (waiting and
confirmed deletes; not ones that gave up) -- review, 2026-10-06:

- **"Copy from…"** (`CopyMealPlanner.plan(excludingLogIds:)`): an entry
  that is being deleted is not offered for copying.
- **the goal judgement** (`GoalStatusEvaluator.evaluate(_:fuel:
  excludingLogIds:)`): the entry's calories and macros come off Garmin's
  totals before the day is judged, so a day is not recorded as "goal met"
  on the strength of an entry being deleted. After a drain each delete's
  own day is judged again (confirmed: gone; gave up: back), not just the
  day on screen; so are "Retry" and "Keep entry" from the sync queue.

### D4. Standalone mode is unchanged; a queued edit's original is queued too

`ModeRoutingFoodLogging.deleteCommitted` still goes to the local food log
in standalone mode. Deleting a row that never reached Garmin still cancels
it in the outbox.

Deleting a queued *edit* of a Garmin entry cancels the edit and must also
delete the original, or "Delete" would only bring the old amount back. That
second half was a direct Garmin call from the screen: offline it failed
after the edit was already cancelled, so the intent was lost (review,
2026-10-06). It now goes through the queue like every other delete
(`PendingDeletion.originalToDelete(in:)`, then `deleteCommitted`), and
nothing in the delete path waits for the network.

Decided for standalone mode: nothing is queued. Such a row can only be a
leftover from before the switch; standalone mode makes no Garmin call and
keeps nothing to send later (the rule "Keep on this phone" already
follows), so the cancelled edit leaves the phone's day and the original
stays in Garmin. The direct call that used to be made here even in
standalone mode is gone.

### D5. Quick logging: one rule for both shelves

`QuickLogShelfPolicy.showsShelf(on:hasItems:allowsFutureDays:)`: a shelf
with something in it shows on a past day and on today, and on a future day
only where the day switcher can reach one (the training experience). The
confirm screens already take the day being viewed (`presetDate`), so
nothing else changes.

### D6. Closing a day is a local fact

`FoodDayCloseStore` keeps `food-day-closes.json`: one record per closed
day (`day`, `closedAt`, `entryCount`, `editedAt`). Rules
(`FoodDayCloseRules`):

- a day can be closed when it has at least one entry and is not in the
  future; undo removes the record;
- a change to a closed day (an entry added, edited, moved, duplicated,
  copied in or deleted through this app) sets `editedAt`. The day stays
  closed and says "Edited after closing". Closing it again (undo, close)
  clears the mark.
- the complete-days streak is the run of closed days ending today, or
  ending yesterday while today is still open; a gap ends it. An edited day
  still counts.

*Alternative for "edited":* compare a fingerprint of the day's entries with
the one taken at closing. Refused: a row's amount is not stable between
"queued" and "read back from Garmin" (`LoggedFood.matchesQuantity` accepts
two different fields), and a day that is not loaded yet has no entries at
all, so the fingerprint would report edits that never happened. The cost of
the chosen rule: an entry changed in Garmin Connect is not noticed.

The file is user data: it is in backups (catalog area `history`, so the
import preview does not count its records as food entries).

### D7. The reminder and the habit read the store, never the reverse

- `TrainingReminderPlanner.plan` takes the closed food days. The evening
  habits reminder of a day that is not closed says "Tick today's habits and
  close your food log."; of a closed day, what it said before. Without the
  set (food-first never plans training reminders) nothing changes.
- `FoodLogHabit.tick(closed:on:snapshot:today:)` decides whether closing
  (or re-opening) a day is also a habit tick: only when the app may record
  ticks, the ladder has a habit with id `food-log` that takes ticks, the
  plan expects it on that day, the day is inside the vault's back-fill
  window and the habit is not already in that state. The app then calls
  `TrainingModel.setHabit`, the same call the Habits card makes. The id is
  the vault's to define; the app only knows the string.

### D8. The carb-load target and the race

`DayFuelTargets.resolve` on a carb-load day: `carbsG`, else `carbsGPerKg` x
weight, else the `{ min, max }` band x weight. It also carries
`carbLoadRaceId`. The app's bridge looks the race up by id
(`TrainingSnapshot.race(id:)`) and passes its name to FoodLogCore, which
never imports TrainingCore.

`FuelDaySummary` gains `raceName` and `targetStatus`: with a single target
(the band's two ends are equal) the day is "Below target" or "Target
reached"; with a band it keeps "Below range / In range / Above range".

### D9. Race badges follow the plan, the tag is the fallback

The plan's facts are already in `FeatureContext.trainingPlan` (nil outside
the training experience). `SportRules` reads them:

- **Race Day Fuel:** a day up to today with at least one entry that is
  tagged `race` *or* is the date of a race in the plan.
- **Carb Loader:** for a race of the plan that has carb-load days
  (`carbLoadRaceId`), every one of those days must have met its carb target
  (`goalStatus.metCarbGoal`, which in the training experience is judged
  against the plan's grams). A race without carb-load days in the plan, and
  every day without a plan, keeps today's rule: a `race`-tagged day whose
  two preceding days met the carb goal.

No badge is added and no badge id changes.

## Risks / Trade-offs

- **The delete route is still not exercised by this project.** A queue
  makes a wrong route louder, not quieter: five failed attempts, then
  "Couldn't delete" on the row and in the sync queue. Mitigation: the route
  and body are unchanged from the direct call the app made before.
- **A delete confirmed by Garmin but not yet read back** is hidden by the
  `.sent` record. If that record were lost (a quarantined file), the row
  reappears until the next read; nothing is deleted twice (404).
- **A delete Garmin answered but did not apply** stays hidden only until
  the day is read again five minutes or more after the answer; a day that
  is never read again keeps the record for a week, then shows the entry.
- **"Edited after closing" misses edits made in Garmin Connect** (D6).
- **A `food-log` tick for a day the vault no longer accepts** is not sent
  (the back-fill window); the day is still closed on the phone.

## Migration Plan

Additive. Two new files appear on first use; an older build ignores both.
`MealEntry` and `FuelDayTarget` gain optional fields with defaults. Rolling
back leaves the two files unused on disk.

## Open Questions

- In standalone mode, deleting a leftover queued edit leaves its original
  in Garmin (D4). If the owner switches back to Garmin, that entry is there
  again at its old amount. Acceptable, or should the delete wait in the
  queue for that switch?
- Should the complete-days streak earn anything? Deferred to a gamification
  change, which can read `FoodDayCloseStore`.
