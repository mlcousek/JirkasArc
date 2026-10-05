## Why

The vault's contract of 2026-10-01 (training load and gates, still
`schemaVersion` 1 and envelope `v` 1) publishes five things the training
experience needs, and `add-daily-checkin-and-pain-mode` only made sure the
richer files read cleanly -- the app shows none of it and writes none of it:

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

The rule of the training experience holds: **the vault computes, the phone
records and displays.**

## What Changes

- **Wire format (TrainingCore `Events/HubEvent.swift`, the only wire-format
  file).** Two new events, `test.gate {date, walkPain, hopPain, site?,
  note?}` and `session.done {date, sessionId, option?, min?, km?, note?}`,
  and `pains [{site, during?, after?}]` on `session.rpe`. Optional keys are
  written, as `null` when unknown; whole numbers are written without a
  fraction. A fourth byte-exact golden file holds the vault example's own
  four lines (seq 25-28) as this app encodes them.
- **Contract (TrainingCore `Contract/`).** `athlete.gate`, the seven load
  fields of `week.actual`, `unplanned[].flag`, `done.manual` with the
  `manual` values of `done.source` and `done.matchedBy`,
  `session.feedback.pains` and top-level `notices` decode tolerantly: a
  missing number is unknown, never 0.
- **The phone's own events.** `CheckInOverlay` folds the gate tests (last
  per date), the session pains (kept or replaced like the morning pain)
  and the sessions done by hand, with the retractions that undo them. A
  session done by hand shows as done at once and until the vault has read
  the event; after that the projection alone decides.
- **Weekly gate test (pain mode only).** A card under Today's training card
  on Saturday and Sunday, and in the Plan week header of the current week
  on any day: two half-step sliders, the tested site and an optional note,
  then the vault's verdict in words ("Hops 4/10 — speed, hills and jumps
  stay locked"), greyed when the vault calls it stale, with a neutral line
  that a physio check is advised after more than two weeks above 2/10.
  Outside pain mode the card is hidden; the "Something hurts?" flow has one
  small entry to it.
- **Pain during and after a session (pain mode only).** In the session
  detail's "How did it feel?", per site a During and an After half-step
  slider, sent with the RPE. The recorded pain and the vault's session
  pain notes are shown; next morning's pain step shows "yesterday after
  the session: 3 → today: 1" per site when both exist.
- **"The plan is the ceiling".** One line on Today's training card and in
  the Plan week header: "Week 34 of 60 km · 8 km unplanned · longest 21 of
  24 km cap · hills 620 m · hard sessions 1", a missing value shown as
  "–". An unplanned activity the vault flags `over-plan` carries an amber
  "Over plan" badge.
- **Done without a watch.** Session detail → "Mark done (no watch)": the
  option (when the session has options), minutes, kilometres for a run,
  ride or walk, a note. Shown as "Done (logged by hand)"; undone with a
  retraction; works for gym sessions.
- **Notices.** The projection's `notices` are shown as quiet lines at the
  top of Today's training card, in the app's language.

Nothing is persisted in a new file: no `StoreCatalog` entry. Nothing is
sent unless the vault connection can record (the existing recorder's
guard).

## Non-goals

- Running any of the vault's rules on the phone: the gate's verdict, the
  pain notes, the over-plan flag, the longest-run cap and the weekly sums
  are read, never computed (`add-hub-ingest` and its successors on the
  vault's side own them).
- The interactive habit history, streaks and back-filled ticks of the same
  contract: the Habits screen's own change.
- Siri, widgets and lock-screen Controls for any of this: the glanceable
  surfaces' own change.
- Rewards for a gate test or a session done by hand: the gamification
  changes.
- A reminder for the weekly gate test (the card on the weekend is the
  prompt; `reminder-notifications` is untouched).
- A pain or load chart: `add-training-stats`' successor.

## Impact

- **Depends on**: `add-daily-checkin-and-pain-mode` (the re-mirrored
  fixtures, `TrainingSnapshot.day`, pain mode), `add-training-checkins`
  (the recorder and the overlay), `add-plan-editing` (the retraction),
  `add-checkin-pain-score` (the site vocabulary and the pain step).
- **Unblocks**: the Habits screen's history (it reads the same re-mirrored
  contract), rewards for gate tests, a load chart.
- TrainingCore: `Events/HubEvent`, `Events/CheckInOverlay`, new
  `Events/ManualDonePolicy`, `Contract/Projection`, `Contract/Pain`,
  `Contract/OpenEnum`, `Plan/TrainingSnapshot`; new view models
  `ViewModels/GateModels`, `ViewModels/WeekLoadModel`,
  `ViewModels/ManualDoneModels`, `ViewModels/SessionPainModels`; the Today,
  Plan, check-in, pain and session-detail builders; new strings in both
  `.lproj` tables and `TrainingKey`.
- App: `Training/TrainingModel` (four actions), new
  `Training/GateTestCard`, `Training/TrainingTodayCards`,
  `Plan/SessionDetailView`, new `Plan/SessionRecordViews`,
  `Plan/WeekAgendaView`. No change to `TodayView`, the layout catalog, the
  shell or `Localizable.xcstrings` (every new word comes from TrainingCore).
- Behaviour that changes for an existing install: a session the vault says
  was done by hand reads "Done (logged by hand)"; the Plan week header and
  Today show the ceiling line when the projection carries the load fields.
- Not verified here: Swift compiles only in CI; the device check is in
  `tasks.md` section 7.
