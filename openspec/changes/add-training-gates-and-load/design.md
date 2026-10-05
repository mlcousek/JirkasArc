## Context

`add-daily-checkin-and-pain-mode` re-mirrored the vault's contract of
2026-10-01 (training load and gates) and made the app read the richer
files without using them (its D8). This change uses them. What was read,
and when (2026-10-02, the vault's main branch, read-only):

- the contract's semantics 16-21 and its "For the app" list of 2026-10-01;
- the mirrored fixtures: `events.v1.example.jsonl` seq 25 (`test.gate`),
  26 and 27 (`session.done`), 28 (`session.rpe` with `pains`);
  `projection.v1.example.json` (`athlete.gate`, the load fields of every
  non-null `week.actual`, one `flag: "over-plan"`, a session done by hand,
  an activity that won over a manual record, `feedback.pains`, a
  `session-pain` note, `notices: []`); `projection.v1.minimal.json`
  (`gate: null`, one `no-activities-since` notice with `date: null`);
- the vault's fold: `pains` on `session.rpe` is replaced only when the key
  is not `null` (a `null` keeps the earlier answer, like the morning
  pain); a retracted fact leaves the fold; `session.done` is last per
  session; `test.gate` is last per date.

No Swift toolchain here: correctness rests on the package tests in CI.

## Goals / Non-Goals

**Goals:** record the gate test, the session pain and "done without a
watch" through the one recorder; show the vault's gate verdict, load
fields, over-plan flags, manual completions, session pain and notices;
keep every number the vault's.

**Non-Goals:** computing a verdict, a cap, a sum or a flag on the phone;
habit history; reminders, widgets, rewards; a new persisted file.

## Decisions

### D1. Wire format: three additions in the one file

`HubEvent.swift` gains `test.gate`, `session.done` and `pains` on
`session.rpe`. As before, optional keys are written, `null` when unknown
(the contract: "may be absent or null, the app should write them"), keys
are sorted, and a number that is whole is written as an integer (`4`, not
`4.0`; `1.5` stays `1.5`) -- the rule `PainEntry` already follows -- so
the bytes never depend on how a platform prints a double. That holds for
`walkPain`, `hopPain`, `during`, `after` and `km`.

`session.rpe` now always carries `pains` (`null` = not asked), so the RPE
line of the first golden file gains `"pains":null`. The vault reads `null`
as "keep the earlier answer", so a later tap on another RPE number never
erases the pain.

**Golden.** A fourth app golden file, `gates.v1.app.jsonl`, is the vault
example's four lines (seq 25-28: same ids, device, clock and values) as
this app encodes them. Three tests tie them together: the Swift-built
events encode to the file's bytes; the mirrored lines decode and re-encode
to the same bytes, line by line; and each golden line equals its mirrored
line as a JSON object (one optional key the vault's line leaves out,
`during` of the second pain entry, compared as `null`). The vault's lines
are not key-sorted, which is why the bytes are compared through this
app's encoding and the objects directly.

*Alternative:* leave `during` / `after` out when unknown, so the mirrored
line needs no `null`. Refused: the app writes every optional key
elsewhere, and one rule is easier to keep than two.

Bounds are checked before anything is recorded: both gate scores and each
session pain score 0-10 on the half-step grid; a gate note 1-200 UTF-16
units; `min` 1-6000; `km` above 0 and at most 1000; a `session.done` note
1-2000 characters.

### D2. Decoding: every new field may be missing

`GateStatus` (`athlete.gate`): identity is its `date`; the scores are
optional numbers, the two verdicts optional booleans (`nil` = the vault
did not say; never read as "allowed"), `weeksHopAbove2` an optional count,
`stale` false when absent. `WeekActual` gains seven optional fields; a
`null` stays `nil` and is drawn as "–". `ActivityRef.flag` is an open
enumeration (`over-plan`). `Done.manual` is the record of what was said;
`DoneSource.manual` and `MatchedBy.manual` become known values.
`SessionFeedback.pains` is `nil` (not asked) or a list of
`SessionPainEntry {site, during?, after?}` (an unknown site reads as
`other`). `Projection.notices` is a lossy list of `{kind, date, en, cz}`;
an entry without text is dropped, an unknown `kind` is kept and shown.

### D3. The phone's own facts ride the existing overlay

`CheckInOverlay` already folds "latest wins" facts with their delivery
state. It gains:

- `gateTests`: per date, the last test;
- `sessionPains`: per session, the `pains` of the last `session.rpe` that
  carried them (the vault's keep/replace rule);
- `manualDone`: per session, the last `session.done` that this phone has
  not retracted, with its event id; and `manualDoneUndone`: per session,
  the ids of retracted `session.done` events with the retraction's
  delivery.

A session done by hand is laid over the plan like a check-in light: while
its event is **not acknowledged**, a session the file does not show as
done becomes `done` with `source: manual` (skipped sessions stay
skipped). While a retraction is not acknowledged, a session the file
shows as done by that very event goes back to `planned` (or `missed`
before `asOf`). Once the vault has acknowledged the event, the projection
alone decides -- so a completion the vault did not count never stays on
screen. The week's sums are not touched: `actual` is the vault's.

*Alternative:* a new overlay type. Refused: the fold, the delivery rule
and the snapshot plumbing would be copied for three more maps.

### D4. The gate card: the phone records, the vault judges

`GateCardModel` is built in pain mode only (`TrainingSnapshot.painMode`):

- on **Today**, under the training card, when the shown day is the
  current training day and a Saturday or Sunday -- the weekly rhythm
  without a reminder. The editor is open while the ISO week has no test
  (the vault's or this phone's), else folded behind "Test again";
- in the **Plan week header** of the week containing today, on any day,
  folded behind "Record a test";
- outside pain mode nowhere, except one small link inside the "Something
  hurts?" step (the same editor; the vault accepts a test at any time and
  keeps publishing the last value as history).

The verdict is the vault's: `runAllowed`, `speedAllowed`,
`weeksHopAbove2`, `stale`. The card words them ("Walking 1.5/10 — running
is allowed", "Hops 4/10 — speed, hills and jumps stay locked"); when
running is not allowed the speed line is locked whatever `speedAllowed`
says (the contract's rule). The one number the app compares is the
contract's own display rule: the physio line shows when
`weeksHopAbove2 > 2`. A stale test is greyed and says so.

Between Save and the next projection the card shows the phone's own test
("Your test of Sat 26 Oct: walking 1.5/10 · hops 4/10 · Saved on phone")
and that the plan answers with the next sync -- never a verdict the phone
worked out. The sliders start at 0, or at today's test when there is one.
The site defaults to the last test's, else the first Achilles site of the
pain episode, else the pain step's default site.

### D5. Session pain travels with the RPE

`session.rpe` needs an `rpe`, so the pain block's Save is enabled once an
RPE is chosen and sends that RPE again with `pains`. Rows start from the
recorded answer, else from the pain episode's sites at 0 / 0. Both scores
are sent as numbers (the morning step's precedent: a row at 0 means "no
pain"); a value the vault publishes as `null` is drawn as "–". The block
is built only in pain mode. The vault's `session-pain` and
`pain-not-settled` notes stay where the previous change put them (with the
session's other rule notes), and can not be overridden.

### D6. "Yesterday after the session → today"

`PainStepModel.settledLines`: for each site that has an `after` score in
a session of the day before (the highest, the phone's answer first) and a
morning score today, one line. Both must exist; nothing is judged -- the
vault writes `pain-not-settled` when it applies.

### D7. The ceiling line

`WeekLoadModel` is built for a week with an `actual` that carries at least
one load field (an older file keeps the old "Run 10.1 of 55 km" line).
Segments, in order: the week's run km of its target; "x km over plan" when
`overPlanKm > 0`; unplanned km; longest of cap; hills; hard sessions. A
`nil` is "–". The over-plan segment and a longest run above its cap are
marked as warnings (amber, with a symbol -- never praise, never colour
alone). The Plan header draws it in place of the run line; Today draws it
under the sessions for the shown day's week.

### D8. Done without a watch

`ManualDonePolicy` offers it when the app may record, the session is in a
written week, its day is today or earlier, and it is neither done nor
skipped. The sheet's defaults are the plan's (`targets.min`, `targets.km`,
the option the morning light points at); kilometres are asked for a run,
ride or walk session. Undo is offered when this phone still holds the
`session.done` (the log keeps 21 days): one `event.retracted` per live
event of that session, because the vault takes the last one that is not
retracted. A completion from another install can not be undone here (the
vault only lets a device retract its own events), so no button is shown.

"Is it manual?" is `done.source == manual`; "was it also said by hand?" is
`done.manual != nil` -- then the activity won and the record is one line
under it.

### D9. Notices

Shown on the current training day only, above the sessions, quiet
(secondary colour, an info symbol). The text is the vault's, resolved in
the app's language like every localized field.

### D10. Nothing new is stored, no new switch

The three facts use the recorder's guard (`canCheckIn` for the gate test,
`canRateSession` for the session pain and done-by-hand). No capability
flag, no UserDefaults key, no file. Every new word is a `TrainingKey`, so
`Localizable.xcstrings`, `TodayView` and the layout catalog are untouched
(other changes are editing them).

## Risks / Trade-offs

- An optimistic "done" disappears if the vault acknowledges the event but
  does not count it (a skipped session, an unknown id) -> that is the
  truth; the ingest report on the desk says why.
- The gate card can not show a verdict until the next projection -> it
  says so, and shows what was sent.
- A whole `km` is written as an integer; a fractional one as Swift prints
  it (shortest round-trip) -> the sheet rounds to 0.1 km first.
- The Today card grows by up to three quiet lines -> each is one line and
  only present when the vault publishes it.

## Migration Plan

None. Older cached projections have none of the new fields: no gate card
verdict ("No gate test yet"), no ceiling line, no notices. Events already
in the local log decode as before (`pains` absent reads as not asked).

## Open Questions

- Should the gate card also appear on Friday evening? (The owner's rhythm
  decides; a week without a test neither counts nor breaks the vault's
  streak.)
