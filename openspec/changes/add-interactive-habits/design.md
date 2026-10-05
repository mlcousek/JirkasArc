## Context

The Habits card on Today (`polish-training-today`) listed the ladder's
habits beside a small on/off toggle, and a read-only ladder sat one tap
behind it. The owner asked for streaks, a done / not done check, logging
and a log history (see the proposal). On 2026-10-01 the vault's projection
(still v1, additive) started to publish `streak`, `history` and
`adherence` for every active habit, and its ingest started to accept a
`habit.tick` for the last 14 days and to answer a refused one in
`outcomes[]`. Branch `mlcousek/interactive-habits`.

## Goals / Non-Goals

Goals: a habit can be ticked in one tap where the owner already looks
(Today); every habit has its own screen with the streak, the adherence,
twelve weeks of history and the recent entries; a past day inside the
vault's 14 can be filled in or taken back; a multi-dose habit counts
doses; the numbers are the vault's, moved only by what the phone knows on
top; nothing is recorded without a working vault connection.

Non-goals: see the proposal. The phone does not replace the vault's
arithmetic, does not start or pause ladder steps and puts no count on the
wire.

## Decisions

### D1 -- One capability, three surfaces, one builder

`training-habits` is a new capability rather than more requirements in
`training-today` / `training-plan-view`: the rules (streak, adherence,
back-fill, refusals) are shared by Today's card, the Habits screen, a
habit's detail and the shortcut, and must be stated once. In code that is
one pure builder, `HabitsBuilder` (TrainingCore `ViewModels/HabitModels`),
with `screen()`, `detail(habitID:)`, `dayControl(habitID:date:)` and
`todayChecks(on:)`; the views draw its models verbatim. Today's card keeps
`HabitsCardModel` for its rows, step and next step and gets the checks
beside it (`HabitChecksModel`), so `polish-training-today`'s tests stand.

### D2 -- The vault's three fields, decoded tolerantly

`Habit` gains `streak { current, best, unit, lastDone }`, `history
[{ date, expected, done }]` (84 days, oldest first after decoding) and
`adherence { d7, d14, d30, d84 }` (`Contract/HabitTracking`). A missing
key, a `null` or a wrong type reads as `nil`; a history entry without a
readable date is dropped and counted (`LossyArray`); a negative count
reads as 0; a percent is kept inside 0...100; an unknown `unit` is kept as
an open enum. **`history == nil` means the file has no such key** (an
older cached file) and is what switches the phone to its fallback (D5);
`[]` on a next or later step is "published, empty".

### D3 -- A day's facts: one resolver, one day lookup

`HabitDayResolver` answers "what was expected and what was done on this
date" in a fixed order:

1. the habit's `history` entry for the date;
2. a day the history covers and does not list: nothing was expected (the
   vault lists every day something was expected or done);
3. the plan's day (`habitsExpected` / `habitsDone`), found through
   **`plan.day(date)` and nowhere else** -- so days outside the written
   weeks (the day skeletons of `add-daily-checkin-and-pain-mode`) are
   found the moment that lookup finds them;
4. a day before the habit started: nothing was expected;
5. otherwise the day is `unknown`.

Then the phone's overlay: its latest kept `habit.tick` for the day wins,
and its dose count fills in a multi-dose day that is not complete. A day
is one of `done`, `partly`, `missed`, `notExpected`, `unknown`, `open`
(expected, not done, and not over yet).

Alternative rejected: walking `weeks[].days[]` in the timeline. It would
have been a second lookup to change when the skeletons arrived.

### D4 -- The streak rule (the owner's, 2026-10-01; the vault's too)

| Day | Effect on the run |
|---|---|
| expected and done (every dose) | extends it |
| expected and not done, the day is over -- **including a day with nothing logged at all** | ends it |
| not expected | neither counts nor ends |
| today, not done yet | neither (the day is not over) |
| unknown (the phone has no facts) | stops the count; the run is "at least" |

A past day with some doses of several is a miss for the streak. The unit
is the vault's (`day`, `week`, `occurrence`); in the fallback it is `day`
for a daily habit and `occurrence` otherwise.

### D5 -- The vault's numbers win; the phone only adds what it knows

With `streak` published the phone shows **that number moved by the
difference between two counts of the same days**: the run as the phone
sees it (its ticks, and the days that ended since the file was written)
minus the run as the file saw it. So with nothing new the vault's number
is shown untouched; a tick today is +1 at once; an un-tick takes it back;
a day that ended silent since the file breaks it. When the two counts end
at different anchors (a broken run, or one joined up to the edge of the
known days) the phone shows what it can count, marked "may be longer". A
`week` streak and a unit this build does not know are never recounted.
`best` is the vault's, or the current one when that is higher.

Adherence works the same way per window (7 / 14 / 30 / 84): the vault's
percent, moved by the phone's own difference only when a tick changed a
complete day inside the window (then marked as an estimate). Adherence
covers complete days ending yesterday and keeps the gate's arithmetic
("unrecorded is not zero": a silent day counts for nothing), so the two
numbers deliberately read a silent day differently, as the vault does.

**Fallback** (no `history` in the file): the same functions over the days
the phone knows. The streak is labelled as counted on the phone with the
number of days it covers; a window the phone does not know in full has no
percent (a dash and one line saying why) rather than a misleading one;
the 14-day tile reuses `window14` when the gate's window is 14 days.

A habit the vault measures itself (`source` activity or plan) takes no
tick, and its days after the file's stay open, never a miss: only the
vault can judge them.

### D6 -- The Habits screen and a habit's detail

The Habits screen replaces `HabitLadderView`: a summary (step n of N,
today's progress, the gate) and one card per step -- established (active,
a later step active too), current (the highest active), locked (with
"Unlocks when <current> holds 80 % over a 14-day window", "Gate met" or
"Unlocks after: <previous>", and its earliest start). An active step shows
its streak, its 14-day window and, when today expects it, the one-tap
check. The detail, top to bottom: header, today's control, current and
best streak, adherence tiles against the gate, the 12-week Monday-first
calendar with a legend, the selected day's panel, the recent entries
(newest first, at most 14, done / partly / missed only), and the refused
ticks when there are any.

### D7 -- A control never records; it says why it is locked

`HabitDayControlModel` is the control for one (habit, day). It is locked,
with one sentence, when: the vault connection is off or untested; the
vault measures the habit itself; the day has not come; the day is older
than the vault's 14; the phone has no record of the day; the plan does
not expect the habit that day. Views call back with the dose count asked
for; `TrainingModel.applyHabit` turns it into the event. A state is never
colour alone: done is a check, missed a cross, partly a half mark,
unknown a dashed outline, today an accent ring.

### D8 -- Today's card

The check leads each expected row and is one tap: done for a single-dose
habit, the next dose for a multi-dose one (a ring with "1/2"); a tap on a
complete day takes **one** dose back, so a mis-tap never wipes a day. The
flame carries the streak number. The row, and a long press ("History"),
open the habit; the header and the next step open the Habits screen. When
the last expected habit of the shown day is ticked the progress line
becomes "All of today's habits done" with a success haptic and one symbol
bounce (no bounce under Reduce Motion). It fires when the shown day
becomes complete, not when the day switcher lands on a day that already
was. The gamification moments overlay is not reused: it is the XP
engine's queue and a habit tick earns no XP here.

### D9 -- Doses stay on the phone; the wire stays on/off

`habit.tick` carries `done: Bool` (decision A42). `HabitDosePolicy` turns
a counter step into: below the day's doses, only the phone's count
changes (`HabitDoseLedger`, one `UserDefaults` value, pruned with the
event log's retention); the last dose records `done: true`; stepping back
from complete, or below what the vault counted, records `done: false`;
"0" on a past day the vault has no count for records `done: false` (an
explicit miss). A step that changes nothing for the vault records nothing.
No new persisted file, so nothing for `StoreCatalog`.

### D10 -- Back-fill and refused ticks

A tick is offered for today and the 14 days before (`HabitBackfill`, the
vault's window), never for a future day. The vault's refusal arrives in
the projection's `outcomes` (`type: "habit.tick"`, `status: "refused"`,
a bilingual reason), matched to the phone's event by id, else by device
and sequence. A refused tick is **not** laid over the plan
(`CheckInOverlay.refusedHabitTicks`): the day keeps what it showed, the
reason is written under that day's control and listed on the habit's
screen, and a later accepted tick of the same day clears it.

### D11 -- The "Tick Habit" shortcut is kept

An App Shortcut in the app target (the fourth of at most five), with two
phrases. It is safe to keep because it goes through the same recorder and
the same guard as a tap: it lists the active, tickable habits from the
cached plan, records `done: true` for today's training day only when the
plan expects the habit today, says so and records nothing otherwise, and
throws the check-in Controls' own errors when the vault connection is off
or untested. It is not a lock-screen Control: the widget extension cannot
read the plan (no App Group on the free team).

### D12 -- The `habits` link

`garminfood://habits` opens the Habits screen and `?habit=<id>` that
habit's detail, on the Plan tab in the training experience (Today in the
food-first one, which has no Habits screen). The id is accepted only as a
short slug; an id the plan does not have shows the empty state. Nothing
sends the link yet; it is the target for later reminders.

## Risks / Trade-offs

- **The phone's delta can disagree with the next file** (a day the vault
  judges differently). Accepted: the next projection replaces it, and the
  delta is only ever applied over days the phone has facts for.
- **Swift compiles only in CI.** The core is pure and covered by
  `HabitTimelineTests` / `HabitModelTests`; the views are thin.
- **A count below the day's doses is lost with the app's preferences.**
  Accepted: it is a same-day note; the vault hears the full dose.
- **Four requirements of three unarchived specs are superseded** (see the
  proposal's Modified Capabilities); the archive must fold them.

## Migration

None. The Habits card keeps its place and id in the Today layout; an
older cached projection shows the fallback until the next fetch.
