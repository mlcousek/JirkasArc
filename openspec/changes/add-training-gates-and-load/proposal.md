## Why

The vault's contract grew twice, additively, still `schemaVersion` 1 and
envelope `v` 1: **training load and gates** (2026-10-01) and **race
results, the fuel log and the recovery window** (2026-10-05, with the same
day's amendment: two times for a race, a recovery window of 14 or 7 days).
`add-daily-checkin-and-pain-mode` only made sure the richer files read
cleanly -- the app shows none of it and writes none of it:

1. **The weekly gate test.** While pain mode is on, running at all and
   running fast, uphill or with jumps are gated by two numbers a week:
   pain when walking and pain on 20 single-leg hops. The vault judges them
   (`athlete.gate`); the phone has no way to record them.
2. **Pain during and after a session.** The morning score says how the
   night went; the pain-monitoring rule is about the session too. The
   vault folds `session.rpe.pains` into `session.feedback.pains` and writes
   the `session-pain` / `pain-not-settled` notes.
3. **"The plan is the ceiling."** `week.actual` now says how much of the
   week's running was planned, how much was not, how far over the target
   it is, the longest run against its cap, the climb and the hard
   sessions. The app shows "Run 34 of 60 km" and nothing else, so an
   unplanned run reads as a bonus.
4. **Done without a watch.** A gym session, or a run with the watch left
   at home, stays "missed" forever. The vault accepts `session.done`.
5. **Data-gap notices.** When no activity has been synced for days, nothing
   is marked done and the app does not say why (`notices[]`).
6. **Race results.** A race has no outcome in the app: the Race screen
   stops at the plan, and the race rewards of
   `add-training-gamification-and-150-levels` (finished, goal reached,
   personal record, wise call) have been dormant since they were built,
   waiting for `season.races[].result`.
7. **The fuel log.** Every long run is a fuelling rehearsal, and nothing
   records what was eaten. The vault accepts `session.fuel` and answers
   with grams per hour against the plan.
8. **The recovery window.** After a long race the vault publishes
   `athlete.recovery` -- day `day` of `of` -- and Today says nothing.

The rule of the training experience holds: **the vault computes, the phone
records and displays.**

## What Changes

- **Wire format (TrainingCore `Events/HubEvent.swift`, the only wire-format
  file).** Four new events -- `test.gate {date, walkPain, hopPain, site?,
  note?}`, `session.done {date, sessionId, option?, min?, km?, note?}`,
  `session.fuel {date, sessionId, carbsG, fluidMl?, durationMin?, note?}`,
  `race.result {raceId, status, reason?, time?, officialTime?, distanceKm?,
  laps?, note?}` -- and `pains [{site, during?, after?}]` on `session.rpe`.
  Optional keys are written, as `null` when unknown, with three exceptions
  where the vault's own example line leaves the key out (`officialTime`,
  `pains` on a rating that did not ask, `during` / `after` of one site);
  whole numbers are written without a fraction. A fourth byte-exact golden
  file holds the vault example's own six lines (seq 25-28, 32, 33) as this
  app encodes them, and each is the same JSON object as the vault's line.
- **Contract (TrainingCore `Contract/`).** `athlete.gate`,
  `athlete.recovery`, the seven load fields of `week.actual`,
  `unplanned[].flag`, `done.manual` with the `manual` values of
  `done.source` and `done.matchedBy`, `session.feedback.pains` and
  `.fuel`, `season.races[].result` and top-level `notices` decode
  tolerantly: a missing number is unknown, never 0; a three-state Boolean
  (`runAllowed`, `goalReached`, `pr`) stays "not known".
- **The phone's own events.** `CheckInOverlay` folds the gate tests (last
  per date), the session pains (kept or replaced like the morning pain),
  the sessions done by hand, the fuel logs and the race results, with the
  retractions that undo them. A session done by hand shows as done at once
  and until the vault has read the event; after that the projection alone
  decides.
- **Weekly gate test (pain mode only).** A card of its own under Today's
  training card on Saturday and Sunday, and one link in the card's pain
  area on other days: two half-step sliders, the tested site and an
  optional note, then the vault's verdict in words ("Hops 4.5/10 — speed,
  hills and jumps stay locked"), greyed when the vault calls it stale, with
  a neutral line that a physio check is advised after more than two weeks
  above 2/10. Hidden outside pain mode.
- **Pain during and after a session (pain mode only).** In the session
  detail's "How did it feel?", per site a During and an After half-step
  slider, sent with the RPE. The recorded pain and the vault's session
  pain notes are shown; next morning's pain step shows "yesterday after
  the session: 3/10 → today: 1/10" per site when both exist.
- **"The plan is the ceiling".** One line on Today's training card and in
  the Plan week header: "Week 34 of 60 km · 8 km unplanned · longest 21 of
  24 km cap · hills 620 m · hard sessions 1", a missing value shown as
  "–". Over the target and a longest run above its cap are warnings (the
  warning tint and a symbol). An unplanned activity the vault flags
  `over-plan` carries an amber "Over plan" badge -- never praise.
- **Done without a watch.** Session detail → "Mark done (no watch)": the
  option (when the session has options), minutes, kilometres for a run,
  ride or walk, a note. Shown as "Done (logged by hand)"; undone with a
  retraction; works for gym sessions.
- **Notices.** The projection's `notices` are quiet lines at the top of
  Today's training card, in the app's language.
- **Race result.** The Race screen shows the vault's result in neutral
  words (finished / did not finish / did not start, with the reason): the
  organiser's `officialTime` first when present and the elapsed `time` as
  the second line, laps, distance, "Goal reached", "Personal record". A
  result sheet on or after race day (only "Did not start" before it) sends
  `race.result`, with a reason picker that includes "Stopped by the stop
  rule"; a result the vault refused shows the vault's reason; Withdraw
  retracts it.
- **Race rewards wake up.** `ProjectionRewardExtras` / `TrainingPlanFacts`
  read the real `result` (`status`, `reason: "stop-rule"`, the three-state
  `goalReached` and `pr`), so the dormant rewards are released from what
  the vault published -- never from this phone's own unread result.
- **Fuel log.** For a long session (2 h or more), a session with a fuel
  plan and a race session: carbs (g), fluid (ml), an optional duration and
  a note; the vault's grams per hour against the plan with a neutral
  below / on / above chip.
- **Recovery chip.** "Recovery day 1 of 14 · until 18 Oct" on Today, the
  length read from `of` (it can be 7), with one generic line of meaning.

Nothing is persisted in a new file: no `StoreCatalog` entry. Nothing is
sent unless the vault connection can record (the existing recorder's
guard). No new badge.

## Non-goals

- Running any of the vault's rules on the phone: the gate's verdict, the
  pain notes, the over-plan flag, the longest-run cap, the weekly sums,
  grams per hour, the fuel verdict, "goal reached", "personal record" and
  the recovery window are read, never computed.
- Blocking or editing a session on the gate or on the recovery window:
  both are information.
- The interactive habit history, streaks and back-filled ticks of the same
  contract (`add-interactive-habits`).
- Siri, widgets and lock-screen Controls for any of this.
- New rewards (for a gate test, a fuel log or a session done by hand) and
  any change to a reward amount: only the existing race rewards wake up.
- A reminder for the weekly gate test (the card on the weekend is the
  prompt; `reminder-notifications` is untouched).
- A pain, load or fuelling chart (`add-training-stats`' successor).
- A gate card in the Plan week header (the earlier draft had one): Today
  and the pain flow are where the test is recorded.

## Impact

- **Depends on**: `add-daily-checkin-and-pain-mode` (`TrainingSnapshot.day`,
  pain mode), `add-training-checkins` (the recorder and the overlay),
  `add-plan-editing` (the retraction, the vault's outcomes),
  `add-checkin-pain-score` (the site vocabulary and the pain step),
  `add-season-phase-race-screens` (the Race screen),
  `add-training-gamification-and-150-levels` (the race rewards).
- **Unblocks**: rewards for gate tests and fuel logs, a load chart.
- TrainingCore: `Events/HubEvent`, `Events/CheckInOverlay`,
  `Contract/Projection`, new `Contract/LoadAndResults`, `Contract/Pain`,
  `Contract/OpenEnum`, `Contract/ProjectionRewardExtras`,
  `Plan/TrainingSnapshot`, `Plan/TrainingPlanFacts`; new view models
  `ViewModels/GateModels` (gate card, week load, recovery chip, notices),
  `ViewModels/SessionRecordModels` (session pain, mark done, fuel log,
  typed numbers), `ViewModels/RaceResultModels`; the Today, Plan, pain,
  session-detail and race builders; new strings in both `.lproj` tables
  and `TrainingKey`; the mirrored contract fixtures (re-mirrored
  2026-10-05) and a fourth golden event file.
- App: `Training/TrainingModel` (six actions, the Today builder's current
  day), new `Training/GateAndLoadViews`, `Training/TrainingTodayCards`,
  `Plan/SessionDetailView`, new `Plan/SessionRecordViews`, new
  `Plan/RaceResultViews`, `Plan/RaceDetailView`, `Plan/WeekAgendaView`, one
  callback in `Today/TodayView`. No change to the layout catalog, the
  shell or `Localizable.xcstrings` (every new word comes from TrainingCore).
- Behaviour that changes for an existing install: a session the vault says
  was done by hand reads "Done (logged by hand)"; the Plan week header and
  Today show the ceiling line when the projection carries the load fields;
  the race rewards are granted once the projection carries a result.
- Not verified here: Swift compiles only in CI; the device check is in
  `tasks.md` section 8.
