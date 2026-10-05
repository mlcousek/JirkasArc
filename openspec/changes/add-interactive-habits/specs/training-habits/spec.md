## ADDED Requirements

### Requirement: The Habits screen shows the ladder as steps

In the training experience the app SHALL offer a Habits screen that lists
the plan's habit ladder in step order. Each step SHALL be shown as
established (active, with a later step active too), current (the highest
active step) or locked (not started), as text and a symbol, never colour
alone. A locked step SHALL say what unlocks it -- "Gate met" when the
vault says the current step's gate is met, else the current habit with the
gate's percentage and window, else the step it comes after -- and its
earliest start when the plan gives one. An active step SHALL show its
current streak and its 14-day window against the gate, and, when today's
plan expects it, the same one-tap check as Today's Habits card. The screen
SHALL show "Step n of N", how many of today's expected habits are done and
the gate. It SHALL offer nothing to start, pause or reorder a step. A plan
without a ladder SHALL show an empty state.

The Habits screen SHALL be reachable from Today's Habits card (its header
and its next step), from the Plan tab's toolbar, and from a
`garminfood://habits` link. Tapping a step SHALL open that habit's detail.

#### Scenario: Two active steps and four locked

- **WHEN** the ladder has six habits, the first two active and the third next
- **THEN** the first is "Established", the second "Current step", the others "Locked", the summary says "Step 2 of 6", and the third says "Unlocks when <second habit> holds 80 % over a 14-day window"

#### Scenario: The gate is met

- **WHEN** the vault says the current step's gate is met
- **THEN** the next step says "Gate met" and the current step shows it too

#### Scenario: A plan without habits

- **WHEN** the plan has no habit ladder
- **THEN** the screen shows "No habits in this plan" and no steps

### Requirement: A habits link opens the Habits screen or one habit

The app SHALL handle `garminfood://habits` by opening the Habits screen
and `garminfood://habits?habit=<id>` by opening that habit's detail, on
the Plan tab in the training experience. In the food-first experience,
which has no Habits screen, the link SHALL open Today. A `habit` value
that is not a short slug of letters, digits, `-` and `_` SHALL be ignored
(the link then opens the Habits screen), and an id the plan does not have
SHALL show an empty state rather than fail.

#### Scenario: A link to one habit

- **WHEN** `garminfood://habits?habit=holds` is opened in the training experience
- **THEN** the Plan tab is selected and the detail of the habit `holds` is pushed

#### Scenario: A malformed id

- **WHEN** the link's `habit` value contains a slash or is longer than 64 characters
- **THEN** the Habits screen opens

### Requirement: A habit's detail shows today, streaks, adherence, history and entries

A habit's detail SHALL show, for an active habit: a control for today (see
"A day's control"); the current and the best streak with the day they were
last done; adherence over 7, 14, 30 and 84 days, each against the ladder's
gate; a calendar of the last twelve weeks, Monday first, ending with
today's week; and the recent entries, newest first, at most fourteen, of
the days that were done, partly done or missed, each with where the
phone's own tick is (saved on the phone, sent, received by the vault). A
locked habit SHALL show what unlocks it and no control for today.

Every calendar day up to today SHALL show one of: done, partly (some
doses of several), missed, not planned, no record; today, while expected
and not done, SHALL show as open rather than missed; a day after today
SHALL be dimmed and not selectable. A state SHALL be distinguishable
without colour, and the calendar SHALL carry a legend of the five states.

#### Scenario: An active daily habit

- **WHEN** an active habit was done on each of the last five days and missed the day before
- **THEN** the detail shows a current streak of 5, the four adherence tiles, twelve weeks of days and the recent entries newest first, the miss among them

#### Scenario: A locked habit

- **WHEN** the detail of a habit that has not started is opened
- **THEN** it shows "Locked", what unlocks it and no control for today

#### Scenario: Today is still open

- **WHEN** today expects the habit and nothing is ticked yet
- **THEN** today's calendar day is open, not missed, and the control says "Not done yet"

### Requirement: The streak follows the owner's rule

A habit's streak SHALL be counted back from today as follows: an expected
day with every dose done extends it; an expected day that is over and not
done ends it, **including a past expected day on which nothing was
recorded at all**; a day the habit was not expected on neither counts nor
ends it; today, while not done, neither counts nor ends it. A past day
with only some of its doses done SHALL end it. Where the phone has no
facts about a day, the count SHALL stop there and the streak SHALL be
marked as possibly longer rather than as broken.

A day's facts SHALL come from the habit's published history, else from the
plan's day for that date, and the plan's day SHALL be looked up through
the plan's one day lookup (`plan.day(date)`), so that a day outside the
written weeks is found whenever that lookup finds it.

#### Scenario: A silent past day

- **WHEN** the habit was expected yesterday, nothing was recorded for yesterday, and it was done on the three days before
- **THEN** yesterday is a miss and the streak is 0

#### Scenario: Today does not break it

- **WHEN** the habit was done on each of the last four days and today is not ticked yet
- **THEN** the streak is 4

#### Scenario: A day that was not expected

- **WHEN** the habit is expected on weekdays, was done Friday and Monday, and today is Monday
- **THEN** the weekend neither counts nor breaks, and the streak includes both days

#### Scenario: The phone runs out of days

- **WHEN** every day the phone knows was done and the habit started before them
- **THEN** the streak is the number of those days and is marked "may be longer"

### Requirement: The vault's numbers win and the phone adds only what it knows

When the projection publishes a habit's `streak` and `adherence`, the app
SHALL show those numbers, changed only by what the phone knows and the
file does not: its own ticks that are still kept, and expected days that
ended since the file was written. With nothing new the vault's numbers
SHALL be shown unchanged. A tick for today SHALL raise the shown streak by
one at once; an un-tick SHALL take it back; a streak counted in weeks, or
in a unit this build does not know, SHALL never be recounted on the phone.
Adherence SHALL cover complete days ending yesterday, so a tick for today
never changes it, and a past day on which nothing was recorded SHALL count
for nothing in it (the gate's arithmetic).

When the cached projection has no habit history, the app SHALL count the
streak and the adherence from the days it knows, SHALL say that the streak
was counted on the phone and over how many days, and SHALL show no percent
for a window it does not know in full.

The three fields SHALL be decoded tolerantly: a missing key, a `null` or a
value of the wrong type reads as absent, a history entry without a
readable date is dropped, a negative count reads as zero, and a percent is
kept within 0 to 100.

#### Scenario: Nothing new on the phone

- **WHEN** the vault publishes a streak of 9 and the phone has no tick of its own
- **THEN** the detail shows 9 and no "counted on this phone" note

#### Scenario: A tick today

- **WHEN** the vault publishes a streak of 9 and the owner ticks today's habit
- **THEN** the streak shows 10 immediately, before anything is uploaded

#### Scenario: A week streak

- **WHEN** the vault publishes a streak of 3 weeks and the owner ticks today
- **THEN** the streak still shows 3 weeks

#### Scenario: An older cached file

- **WHEN** the cached projection has no `history` for the habit and the plan covers three weeks
- **THEN** the streak says it was counted on the phone over those days, and the 30- and 84-day tiles show a dash with a line saying why

### Requirement: A day's control records done or not done, and counts doses

For a day the plan expects a habit on, the app SHALL offer a control: for
a habit done once a day, a single check that toggles done and not done;
for a habit with several doses a day, a count with one more and one fewer
and the count shown as "n/N". On Today's card and the Habits screen one
tap SHALL add the next dose, and one tap on a complete day SHALL take one
dose back, never clear the day.

Every change SHALL be recorded through the check-in recorder as a
`habit.tick` with the day, the habit and `done` as on or off: locally,
durably and without waiting for the network. The wire SHALL only carry on
or off: a count below the day's doses SHALL be kept on the phone and
recorded as nothing; the last dose SHALL record done; a step back from a
complete day SHALL record not done. A step that changes nothing for the
vault SHALL record nothing.

The control SHALL be disabled, with one sentence saying why, when the
vault connection is off or not tested, when the vault measures the habit
itself (from activities or the plan), when the day has not come, when the
day is older than the back-fill window, when the phone has no record of
the day, and when the plan does not expect the habit that day.

#### Scenario: A single-dose habit

- **WHEN** the owner taps the check of a habit expected today
- **THEN** the day shows done at once and one `habit.tick` with `done: true` is recorded

#### Scenario: Two doses a day

- **WHEN** the owner adds the first of two doses
- **THEN** the control shows "1/2", the day is partly done and nothing is recorded for the vault

#### Scenario: The last dose

- **WHEN** the owner adds the second of two doses
- **THEN** the day shows done and one `habit.tick` with `done: true` is recorded

#### Scenario: One back from complete

- **WHEN** the owner taps the check of a two-dose day that is complete
- **THEN** the count is 1 of 2 and one `habit.tick` with `done: false` is recorded

#### Scenario: No working vault connection

- **WHEN** the vault connection is off or was never tested
- **THEN** the control is disabled, says that the habit can't be recorded without the vault connection, and nothing is recorded

#### Scenario: A habit the vault measures

- **WHEN** the habit's source is the owner's activities
- **THEN** no day of it can be ticked and the control says the vault measures it

### Requirement: A past day can be filled in or taken back within 14 days

In a habit's detail, selecting a calendar day SHALL show that day's state
and, for a day the plan expected the habit on that is today or at most 14
days back, "Mark done" and "Mark not done" (or the dose count for a
multi-dose habit). Marking a done day not done SHALL un-tick it. A day
after today SHALL NOT be offered, and a day older than 14 days SHALL say
that it can no longer be changed. The streak, the adherence, the calendar
and the entries SHALL reflect the change at once.

#### Scenario: Filling in yesterday

- **WHEN** yesterday was expected and missed and the owner marks it done
- **THEN** yesterday shows done, a `habit.tick` for yesterday with `done: true` is recorded, and the streak joins the runs on both sides

#### Scenario: Un-ticking

- **WHEN** the owner marks a done day inside the window not done
- **THEN** a `habit.tick` with `done: false` is recorded for that day and the streak is broken there

#### Scenario: Too old

- **WHEN** the owner selects a day 15 days back
- **THEN** the panel says the day is older than 14 days and offers no buttons

#### Scenario: A day that has not come

- **WHEN** Today's day switcher shows tomorrow
- **THEN** the habit's check is disabled and says the day hasn't come yet

### Requirement: A tick the vault refused is shown with its reason

When the projection's `outcomes` say that the vault refused one of this
phone's habit ticks, the app SHALL NOT show that tick as done or not
done: the day SHALL keep what it showed without it. The vault's reason, in
the app's language (a plain sentence when it gave none), SHALL be shown
under that day's control and in a "Not accepted by the vault" list on the
habit's detail. A later tick of the same day that the vault did not refuse
SHALL clear the refusal.

#### Scenario: A refused back-fill

- **WHEN** the phone ticked a day and the next projection carries a refused outcome for that event with a reason
- **THEN** the day is not shown as done, and the reason is shown under the day's control and in the habit's list of refused ticks

#### Scenario: Another tick of another day

- **WHEN** one tick was refused and the phone has another tick for a different day
- **THEN** only the refused one is taken out; the other still shows

### Requirement: Today's Habits card ticks in one tap and celebrates a complete day

In Today's Habits card each habit the shown day expects SHALL lead with a
check that records in one tap (see "A day's control"), and each shown
habit SHALL carry its current streak as a number beside a flame, lit while
the streak runs. Tapping the rest of a row, or choosing "History" after a
long press, SHALL open that habit's detail; the header and the next step
SHALL open the Habits screen. The card SHALL show how many of the shown
day's expected habits are done, counting a multi-dose habit only when all
its doses are done.

When the last expected habit of the shown day becomes done, the card SHALL
show "All of today's habits done" with a success haptic and one short
symbol animation; with Reduce Motion on there SHALL be no animation. The
celebration SHALL NOT play when the day switcher moves to a day that was
already complete.

#### Scenario: One tap

- **WHEN** the owner taps the check of an expected single-dose habit on Today
- **THEN** the row shows done, the streak number rises by one and "1 of 2 done today" is shown

#### Scenario: The last habit of the day

- **WHEN** the owner ticks the last expected habit of the shown day
- **THEN** the progress line becomes "All of today's habits done" with a success haptic

#### Scenario: A habit not on the day's plan

- **WHEN** an active habit is not expected on the shown day
- **THEN** its row has no check, still shows its streak and still opens its detail

#### Scenario: Reduce Motion

- **WHEN** Reduce Motion is on and the day becomes complete
- **THEN** the text and the haptic appear without the symbol animation

### Requirement: A Tick Habit shortcut marks a habit done for today

The app SHALL offer a "Tick Habit" App Shortcut, available to Siri and
Shortcuts with phrases that include the app's name, in English and Czech.
It SHALL offer the ladder's active habits that take a tick, from the
cached plan, and SHALL record `habit.tick` with `done: true` for today's
training day through the same recorder as a tap. It SHALL record nothing
and say so when the plan does not expect the habit today, and SHALL fail
with a localized message, recording nothing, when the vault connection is
off or not tested or the habit is not in the plan.

#### Scenario: Ticking by voice

- **WHEN** the owner says the shortcut's phrase and picks a habit that today's plan expects
- **THEN** one `habit.tick` with `done: true` for today's training day is recorded and the answer names the habit

#### Scenario: Not on today's plan

- **WHEN** the picked habit is not expected today
- **THEN** nothing is recorded and the answer says it isn't on today's plan

#### Scenario: The vault connection is off

- **WHEN** the shortcut runs with the vault connection off
- **THEN** nothing is recorded and the shortcut reports that the vault connection is off
