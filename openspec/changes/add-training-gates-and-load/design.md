## Context

`add-daily-checkin-and-pain-mode` re-mirrored the vault's contract of
2026-10-01 (training load and gates) and made the app read the richer
files without using them (its D8). This change uses them, and the
additions of 2026-10-05 with them. What was read, and when (2026-10-02 and
2026-10-05, the vault's main branch, read-only):

- the contract's semantics 16-24 and its three "For the app" lists
  (2026-10-01, 2026-10-05 and the amendment of 2026-10-05);
- the mirrored fixtures, re-mirrored 2026-10-05:
  `events.v1.example.jsonl` seq 25 (`test.gate`), 26 and 27
  (`session.done`), 28 (`session.rpe` with `pains`), 32 (`race.result`) and
  33 (`session.fuel`); `projection.v1.example.json` (`athlete.gate`, the
  load fields of every non-null `week.actual`, one `flag: "over-plan"`, a
  session done by hand, an activity that won over a manual record,
  `feedback.pains`, a `session-pain` note, `notices: []`, four races with
  two results -- one with an `officialTime` beside its `time` -- one fuel
  log, `athlete.recovery` day 10 of 14); `projection.v1.minimal.json`
  (`gate: null`, `recovery: null`, one `no-activities-since` notice with
  `date: null`);
- the vault's fold: `pains` on `session.rpe` is replaced only when the key
  is present and not `null` (absent or `null` keeps the earlier answer,
  like the morning pain); a retracted fact leaves the fold; `session.done`,
  `session.fuel` are last per session, `race.result` last per race,
  `test.gate` last per date; a `finished` / `dnf` sent before race day is
  refused with an outcome.

`season.races` has four entries with a marathon at index 1: **a race is
looked up by `id`, never by position.**

No Swift toolchain here: correctness rests on the package tests in CI.

## Goals / Non-Goals

**Goals:** record the gate test, the session pain, "done without a watch",
the fuel log and a race result through the one recorder; show the vault's
gate verdict, load fields, over-plan flags, manual completions, session
pain, notices, race results, fuel verdict and recovery window; wake the
race rewards from the published result; keep every number the vault's.

**Non-Goals:** computing a verdict, a cap, a sum, a flag, grams per hour,
"goal reached" or a recovery window on the phone; habit history;
reminders, widgets, new rewards; a new persisted file.

## Decisions

### D1. Wire format: five additions in the one file

`HubEvent.swift` gains `test.gate`, `session.done`, `session.fuel`,
`race.result` and `pains` on `session.rpe`. Keys are sorted (by code unit,
case-sensitively -- what `JSONEncoder.sortedKeys` does on the platforms
this app runs on), and a number that can carry a fraction goes through
`WireNumber`: a whole value is written as an integer (`4`, `10`, `90`),
anything else as an exact `Decimal` (`1.5`, `42.2`), so the bytes never
depend on how a platform prints a binary double. Grids: half steps for
pain scores, 0.01 km for distances, 0.1 g for carbs.

Optional keys are written, `null` when unknown (the contract: "may be
absent or null, the app should write them") -- **with three exceptions,
each one where the vault's own example line leaves the key out**:

- `officialTime` on `race.result` (the contract: "omit it for a race with
  one time, never send a copy of `time`");
- `pains` on a `session.rpe` that did not ask (the vault's seq 9; and
  every rating recorded before this change keeps its bytes -- the first
  golden file is untouched);
- `during` / `after` of one site that was not asked (the vault's seq 28).

Absent and `null` mean the same to the vault, so nothing is lost; what is
gained is one rule that can be tested without an exception list: **this
app's encoding of a vault example line is the same JSON object as the
vault's line.**

**Golden.** A fourth app golden file, `gates.v1.app.jsonl`, is the vault
example's six lines (seq 25-28, 32, 33: same ids, device, clock and
values) key-sorted. Three tests tie them together: the Swift-built events
encode to the file's bytes; each mirrored line decodes and re-encodes to
the golden line byte for byte; and that re-encoding equals the mirrored
line as a JSON object, with no key added and none dropped.

*Alternative (the first draft):* write `pains: null` and `during: null`
always, and compare the objects "with a missing key read as null".
Refused: it changes the bytes of every RPE already in the first golden
file for no gain, and a comparison with an exception is a weaker test.

Bounds are checked before anything is recorded: gate scores and session
pain scores 0-10 on the half-step grid; a gate note 1-200 UTF-16 units;
`min` and `durationMin` 1-6000; `km` above 0 and at most 1000; `carbsG`
0-2000 (0 is an answer); `fluidMl` from 0; a time strictly `h:mm:ss` with
hours without a leading zero; `officialTime` never equal to `time`;
`distanceKm` above 0; `laps` from 0; texts 1-2000 characters. Reading an
event, an unknown race `status` makes the line invalid (it decides
everything else; the vault rejects it too), an unknown `reason` or site is
`other`.

### D2. Decoding: every new field may be missing

`Contract/LoadAndResults.swift` holds the new types. `GateStatus`
(`athlete.gate`): identity is its `date`; the scores are optional numbers,
the two verdicts optional Booleans (`nil` = the vault did not say; never
read as "allowed"), `weeksHopAbove2` an optional count, `stale` false when
absent. `RecoveryWindow` needs `1 ≤ day ≤ of`, else there is no window.
`WeekActual` gains seven optional fields; a `null` stays `nil` and is
drawn as "–". `ActivityRef.flag` is an open enumeration (`over-plan`).
`Done.manual` is the record of what was said; `DoneSource.manual` and
`MatchedBy.manual` become known values. `SessionFeedback.pains` is `nil`
(not asked) or a list of `SessionPainEntry {site, during?, after?}` (an
unknown site reads as `other`); `SessionFeedback.fuel` is a `FuelLog`.
`Race.result` is a `RaceResult` whose `status`, `reason` and `source` are
open enumerations and whose `goalReached` and `pr` are three-state.
`Projection.notices` is a lossy list of `{kind, date, en, cz}`; an entry
without text is dropped, an unknown `kind` is kept and shown.

### D3. The phone's own facts ride the existing overlay

`CheckInOverlay` already folds "latest wins" facts with their delivery
state. It gains:

- `gateTests`: per date, the last test;
- `sessionPains`: per session, the `pains` of the last `session.rpe` that
  carried them (the vault's keep/replace rule);
- `manualDone`: per session, the last `session.done` that this phone has
  not retracted, with its event id; `retractedDone`: the retracted ones
  with the retraction's delivery;
- `fuelLogs` per session and `raceResults` per race (the last not
  retracted; a result named by a refused `race.result` outcome carries the
  vault's reason);
- `liveDoneEventIDs` / `liveRaceResultEventIDs`: every event of a session /
  race still in the fold, and `pendingRaceWithdrawals`.

A session done by hand is laid over the plan like a check-in light: while
its event is **not acknowledged**, a session the file does not show as
done becomes `done` with `source: manual` (skipped sessions stay skipped;
the option counts only when the session has it). While a retraction is not
acknowledged, a session the file shows as done by that very event goes
back to `planned`. Once the vault has acknowledged the event, the
projection alone decides -- so a completion the vault did not count never
stays on screen. The week's sums are not touched: `actual` is the vault's.

*Alternative:* a new overlay type. Refused: the fold, the delivery rule
and the snapshot plumbing would be copied for five more maps.

### D4. The gate card: the phone records, the vault judges

`GateCardModel` is built in pain mode only (`TrainingSnapshot.painMode`:
the vault's word, or this phone's unread pain answer above 0) and for the
current training day only -- it describes now, not a day being browsed
(`TodayTrainingBuilder.today`; the app passes it):

- on **Saturday and Sunday** it is prominent: a card of its own under
  Today's training card -- the weekly rhythm without a reminder;
- on **other days** it is one link in the training card's pain area that
  unfolds the same block; the "Something hurts?" flow leads there, because
  saving a score above 0 in it turns pain mode on;
- outside pain mode it is not built at all, whatever the file's last test
  says (the vault keeps publishing it only as history).

The verdict is the vault's: `runAllowed`, `speedAllowed`,
`weeksHopAbove2`, `stale`. The card words them ("Walking 1.5/10 — running
is allowed", "Hops 4.5/10 — speed, hills and jumps stay locked"); when
running is not allowed the speed line is locked whatever `speedAllowed`
says (the contract's rule); a verdict the vault did not give shows the
score alone. The one number the app compares is the contract's own
display rule: the physio line shows when `weeksHopAbove2 > 2`. A stale
test is greyed and says so. A lock or a check goes with the words, never
colour alone.

Between Save and the next projection the card shows the phone's own test
("Your test of Wed 23 Oct: walking 2/10 · hops 3/10 · Saved on phone") and
that the plan answers with the next sync -- never a verdict the phone
worked out. The sliders start at 0, or at today's test when there is one.
The site defaults to the last test's, else the first Achilles site of the
pain episode, else the pain step's default site.

*Dropped from the first draft:* a second gate card in the Plan week
header. One place to record a weekly test is enough.

### D5. Session pain travels with the RPE

`session.rpe` needs an `rpe`, so the pain block's Save is enabled once an
RPE is chosen and sends that RPE again with `pains`. Rows start from the
recorded answer, else from the pain episode's sites at 0 / 0. Both scores
of a row are sent as numbers (the morning step's precedent: a row at 0
means "no pain"); a value the vault publishes as `null` is drawn as "–".
The block is built only in pain mode and not before the session's day.
The vault's `session-pain` and `pain-not-settled` notes stay where the
previous change put them (with the session's other rule notes), and can
not be overridden.

### D6. "Yesterday after the session → today"

`PainStepModel.settledLines`: for each site that has an `after` score in
a session of the day before (the highest; the phone's answer for a session
before the vault's) and a morning score today, one line. Both must exist;
nothing is judged -- the vault writes `pain-not-settled` when it applies.
Pain mode only.

### D7. The ceiling line

`WeekLoadModel` is built for a week with an `actual` that carries at least
one load field (an older file keeps the old "Run 10.1 of 55 km" line).
Segments, in order: the week's run km of its target; "x km over plan" when
`overPlanKm > 0`; unplanned km; longest of cap; hills; hard sessions. A
`nil` is "–". The over-plan segment and a longest run above its cap are
marked as warnings (the warning tint with a symbol -- never praise, never
colour alone). The Plan header draws it in place of the run line; Today
draws it under the sessions for the shown day's week. An unplanned
activity the vault flags `over-plan` carries an "Over plan" badge in the
Plan day rows.

### D8. Done without a watch

`ManualDoneModel` offers it when the app may record, the session's day is
today or earlier, and it is neither done nor skipped. The sheet's defaults
are the plan's (`targets.min`, `targets.km`, the option the morning light
points at); kilometres are asked for a run, ride or walk session. Undo is
offered when this phone still holds the `session.done` the session is done
by (the log keeps 21 days) and no activity has matched: one
`event.retracted` per live event of that session, because the vault takes
the last one that is not retracted. A completion from another install can
not be undone here (the vault only lets a device retract its own events),
so no button is shown.

"Is it manual?" is `done.source == manual` -- then the status reads "Done
(logged by hand)" and the done card says what was said; "was it also said
by hand?" is `done.manual != nil` beside an activity -- then the activity
won and the record is one line under it.

### D9. Notices

Shown on the current training day only, at the top of the training card,
quiet (secondary colour, an info symbol). The text is the vault's,
resolved in the app's language like every localized field; an unknown
kind is shown all the same.

### D10. Nothing new is stored, no new switch

Every fact uses the recorder's guard (`canCheckIn` for the gate test,
`canRateSession` for the rest). No capability flag, no UserDefaults key,
no file -- so no `StoreCatalog` entry and no store fixture. Every new word
is a `TrainingKey`, so `Localizable.xcstrings` and the layout catalog are
untouched; the app's views draw TrainingCore's strings verbatim. No new
badge, so `BadgeArtCatalog` is untouched.

### D11. The fuel log

`SessionFuelModel` is built for a session that is one to log fuel for --
a race session, a session with a fuel plan, or one planned or done at
2 h or more -- on or after its day, and for any session that already has
a log. It is its own card after "How did it feel?" (a fuel log needs no
RPE: the vault creates the feedback from the log alone). What is shown is
the vault's: grams and millilitres, `gPerH` against `planGPerH`, and
`vsPlan` as a neutral chip (an arrow or an equals sign and the words; no
judgement colour -- the band is the vault's display convention, not a
rule). Without a known duration the card asks for it. Between Save and the
next projection the phone's own amounts are shown with their delivery;
the verdict is never worked out on the phone. `0 g` is an answer; carbs
are rounded to whole grams.

### D12. The recovery chip

`RecoveryChipModel`: "Recovery day `day` of `of`" with the last day, the
race's name (by `raceId`) and one generic line chosen by the rule AND the
length -- `PM-SEQ-1`: days 1-7 no running, days 8-14 easy only; `PM-SEQ-3`
with 14: no build for two weeks; `PM-SEQ-3` with 7: a week of recovery
after a race that ended early. The two-week text never stands beside a
7-day window; an unknown rule shows the day count only. The bar divides by
`of`. Current training day only. Information: no session is blocked.

### D13. The race result

`RaceResultModel` shows ONE record: the vault's, or -- while the vault has
not read it -- this phone's own with its delivery. The vault's record is
never mixed with the phone's.

- **Two times.** `officialTime` is the result when present, with the
  elapsed `time` as the second line ("21:31:23 elapsed"); when it is
  absent, `time` is the result and there is no second line. Neither is
  copied into the other, on screen or on the wire.
- Neutral words: "Finished", "Did not finish", "Did not start", and the
  reason for the last two. "Goal reached" and "Personal record" only when
  the vault says `true`; `false` and "not known" show nothing.
- The sheet is offered when the app may record and the race report does
  not state the result yet (the report replaces the app's result whole).
  On or after race day: all three statuses. Before it: only "Did not
  start" -- the vault refuses a finish sent early -- and only in the 14
  days before the race (a display choice: an earlier non-start belongs in
  the race register at the desk). Laps are asked for a timed race or one
  that already has laps recorded.
- A result the vault refused (an outcome of type `race.result`) shows the
  vault's reason and is not the result.
- Withdraw retracts every `race.result` of this phone for the race that
  is still in the fold; until the vault has read the retraction, the
  event-sourced record on file is hidden with "The plan answers after the
  next sync."

### D14. The race rewards read the real result

`add-training-gamification-and-150-levels` built the race rewards against
a draft shape (`outcome`, `stopRule`, `fuelPlanFollowed`). The real one
is `status`, `reason`, `goalReached`, `pr`. `ProjectionRewardExtras` reads
the real keys first (the draft's only when those are absent, so its tests
keep their meaning): `status` is the outcome, `reason == "stop-rule"` is
"stopped by the rule". The vault publishes no "fuel plan followed", so
`TrainingPlanFacts` reads the vault's verdict on the race session's fuel
log: `on` is yes, `below` / `above` no, no verdict unknown.

Nothing in Gamification changes: its rules already key every grant by the
race id (`race-finish`, `wise-call`, ...), so a result that arrives, or
changes source from the app's event to the report, grants each reward
once. Only the PUBLISHED result counts -- this phone's unread
`race.result` releases nothing, and a refused one never will.

## Risks / Trade-offs

- An optimistic "done" disappears if the vault acknowledges the event but
  does not count it (a skipped session, an unknown id) -> that is the
  truth; the ingest report on the desk says why.
- The gate card can not show a verdict until the next projection -> it
  says so, and shows what was sent.
- A distance is written on a 0.01 km grid and carbs on 0.1 g -> the sheets
  round coarser first (0.1 km, whole grams); the grid only guarantees
  exact digits.
- `Decimal` in `JSONEncoder`: written digit for digit by Foundation on
  iOS 17 / macOS 14 and later; the golden test would catch a platform that
  did otherwise.
- The Today card grows by up to four quiet blocks (notice, recovery, gate
  link, load line) -> each is present only when the vault publishes it,
  and two of them only in pain mode.
- `SessionRecordViews` and `RaceResultViews` are SwiftUI that was never
  compiled locally -> the logic (payloads, bounds, typed numbers) is in
  TrainingCore and tested there; the views only draw.

## Migration Plan

None. Older cached projections have none of the new fields: no gate
verdict ("No gate test yet" in pain mode), no ceiling line, no notices, no
result card, no recovery chip. Events already in the local log decode as
before (`pains` absent reads as not asked), and a rating recorded now has
the same bytes as before unless the pain was asked.

## Open Questions

- Should the gate card also appear on Friday evening? (The owner's rhythm
  decides; a week without a test neither counts nor breaks the vault's
  streak.)
- Should a gate test or a fuel log earn anything? (Left to a gamification
  change: this one only wakes rewards that already exist.)
