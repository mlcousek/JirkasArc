## Why

The owner, after a few days with the Habits card on Today
(`polish-training-today`): **"I want streaks, I want to check done or not,
I want to log, and a log history as well; make it interactive and
better."**

What the app had: a Habits card whose rows carried a small toggle for the
habits the shown day expects, and a read-only ladder screen one tap behind
it. No streak anywhere, no history, no way to fix yesterday, and a habit
done twice a day was a single on/off switch.

What changed underneath on 2026-10-01: the vault's projection (still v1,
additive) now publishes, for every active habit, a `streak`, an 84-day
`history` and an `adherence` over 7 / 14 / 30 / 84 days, and its ingest
accepts a `habit.tick` for the day it was sent on **and up to 14 days
back**, un-ticks with `done: false`, and answers a tick it refuses (a
future day, an older day) with an entry in `outcomes[]`. The owner also
settled the streak rule that day: **a silent past expected day is a miss
and breaks the streak; today never breaks it before it is over; a day
nothing was expected on neither counts nor breaks.**

So the data and the rule exist; the phone only has to show them, let him
act on them, and stay honest while the vault has not caught up.

## What Changes

- **Habits screen** (replaces the read-only ladder; from Today's Habits
  card, Plan's toolbar and a `garminfood://habits` link): the ladder as
  steps -- established, current, locked with what unlocks it -- each active
  step with its streak, its 14-day window and, when today expects it, the
  same one-tap check as Today.
- **Habit detail** (a row of either surface, or `garminfood://habits?habit=<id>`):
  a big control for today (done / not done; minus, ring, plus for a habit
  with several doses a day), the current and best streak, adherence over
  7 / 14 / 30 / 84 days against the gate, a 12-week calendar (done,
  partly, missed, not planned, no record; today open), the recent entries
  with where the phone's own ticks are (saved, sent, received), back-fill
  of a past day inside the vault's 14 days including un-tick, and the
  vault's reason for a tick it refused.
- **Today's Habits card**: a one-tap check leading each expected habit, its
  streak beside it, the row (and a long press) opening the detail, and a
  small celebration -- "All of today's habits done", a success haptic, one
  bounce -- when the last one is ticked.
- **Data** (TrainingCore): the three new habit fields decoded tolerantly;
  one timeline per habit that merges the vault's history, the plan's own
  days and the phone's ticks; the streak rule above; the vault's numbers
  shown as published and moved only by what the phone knows on top (its
  pending ticks, a day that ended since the file was written); a limited
  fallback, said to be one, when the cached file has no such fields.
- **Recording**: every change goes through the existing check-in recorder
  as `habit.tick {date, habitId, done}` -- local, durable, never a network
  wait, and nothing at all unless the vault connection is on and tested.
  The wire stays on/off (decision A42): doses below a day's full count are
  the phone's own note.
- **"Tick Habit" App Shortcut** (the fourth; app target, no new App ID):
  Siri or Shortcuts asks which active habit and marks it done for today's
  training day from the cached plan.

## Capabilities

### New Capabilities

- `training-habits`: the Habits screen, a habit's detail, streaks,
  adherence, history, back-fill and refused ticks; Today's interactive
  Habits card; the Tick Habit shortcut; the `habits` link.

### Modified Capabilities

None archived. This change supersedes sentences of three unarchived
specs; their archive must fold these together:

- `training-plan-view` (`add-training-today-and-plan`) "The habit ladder
  shows where each habit stands": the ladder screen is now the Habits
  screen and *does* offer a tick; it still offers nothing to start or
  pause a step.
- `training-checkins` (`add-training-checkins`) "Habits are ticked on and
  off": a tick is offered for today and the 14 days before, **not for a
  future day** (the vault refuses it since 2026-10-01), so its scenario
  "Logging tomorrow" no longer holds.
- `training-today` (`polish-training-today`) "The habit ladder is tracked
  from Today": the row's toggle is a leading check with a streak, and a
  row opens the habit.
- `siri-and-shortcuts` (`add-glanceable-surfaces`): four shortcuts, still
  within its five.

## Non-goals

- Computing what the vault computes for good: the phone's own streak and
  percent are a fallback for a file without the new fields, labelled as
  such; with the fields the vault's numbers win.
- Starting, pausing or reordering ladder steps from the phone (a desk
  decision, as before).
- Ticking a habit the vault measures itself from activities or the plan,
  or a day the plan does not expect the habit on.
- Counts on the wire: `habit.tick` stays on/off (A42).
- A lock-screen Control or widget for habits: the widget extension cannot
  read the plan (no App Group on the free team; `add-glanceable-surfaces`).
- XP or achievements for a habit streak (`add-winter-arc-nutrition-and-rewards`
  owns training rewards; its facts already count ticks).
- Looking days up outside the written weeks (day skeletons), pain mode and
  the reminders: `add-daily-checkin-context`'s app side, built in parallel.
  This change finds a day through the one existing lookup, so it picks the
  skeletons up when that lands.
- Any change to the vault or to the event contract.

## Impact

**Depends on**: `add-training-checkins` (the recorder, `habit.tick`, the
overlay), `polish-training-today` (the Habits card, `HabitsCardModel`),
`add-plan-editing` (the `outcomes` reader), and the vault's projection
fields of 2026-10-01 (absent: the fallback).
**Unblocks**: habit reminders that link to a habit (`garminfood://habits`),
a habits widget should shared state ever exist.

- TrainingCore: new `Contract/HabitTracking.swift`, `Plan/HabitTimeline.swift`,
  `ViewModels/HabitModels.swift`; `Habit` gains `streak` / `history` /
  `adherence`; `CheckInOverlay` keeps refused habit ticks apart
  (`refusedHabitTicks`), `TrainingRecorder.overlay(acks:outcomes:)`;
  47 strings in `TrainingKey` and both `.lproj` tables (three plural);
  tests `HabitTimelineTests`, `HabitModelTests`, `Support/HabitFixtures`
  (synthetic, inline).
- App: new `Habits/` (`HabitsScreen`, `HabitDetailView`, `HabitComponents`,
  `HabitsTodayCard`), `Shortcuts/TickHabitIntent.swift`; `Plan/HabitLadderView`
  removed; `TrainingModel` (`habitsBuilder`, `applyHabit`, the dose ledger
  as one preference value), `TodayView`, `PlanTabView`, `AppRouter`,
  `GarminFoodShortcuts`; `Shared/GarminFoodDeepLink` (`habits`); seven app
  strings in `Localizable.xcstrings`, two phrases in `AppShortcuts.xcstrings`.
- No new persisted file (the dose ledger is a `UserDefaults` value, pruned
  with the event log's retention), so nothing to add to `StoreCatalog`.
- No new target, entitlement, App ID or Garmin route.
