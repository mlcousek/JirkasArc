Every task ends with CI green: `swift test` for TrainingCore, the
design-token lint, the app and widget `xcodebuild`, and the `localization`
job. Every new `.swift` file starts with a header comment saying why it
exists and what depends on it. All new user-facing text is in English and
Czech and comes from TrainingCore (`TrainingKey`, both `.lproj` tables);
`Localizable.xcstrings` is not touched. **Fixtures are synthetic** (the
vault example's 2030/31 season); no token, repository name, real vault
data or personal health history in strings, fixtures or docs. Branch
`mlcousek/training-gates-and-load` on `main`. Nothing is persisted in a
new file (no `StoreCatalog` entry, no store fixture) and no badge is added
(`BadgeArtCatalog` untouched). Relative size: S / M / L.

A box is ticked when the code was written and read back against its call
sites and tests; nothing here was compiled locally (no Swift toolchain),
so 8.2 and 8.3 stay open until CI and the phone have said so.

## 1. Contract and fixtures (M)

- [x] 1.1 Re-mirror the four vault contract fixtures verbatim from the vault's main branch (2026-10-05, with the amendment; compared byte for byte; checked for anything non-synthetic) and update the fixtures' `CONTRACT.md`.
- [x] 1.2 Goldens that follow the richer example: a race is looked up by `id` (`Fixtures.raceIndex`; four races, a marathon at index 1), three timeline lanes, two races in the closed prelude's recap, the phone's ack at seq 33, 33 event lines.
- [x] 1.3 `Contract/LoadAndResults.swift`: `GateStatus`, `RecoveryWindow`, `ProjectionNotice`, `ManualDone`, `FuelLog`, `RaceResult` and the open enumerations `ActivityFlag`, `RaceResultReason`, `RaceResultSource`, `FuelVsPlan` -- tolerant, a missing number unknown, three-state Booleans.
- [x] 1.4 `Projection.swift`: `athlete.gate` / `.recovery`, seven load fields on `WeekActual` (`hasLoadFields`), `ActivityRef.flag`, `Done.manual` (`isManual`), `SessionFeedback.pains` / `.fuel`, `Race.result`, `Projection.notices`; `DoneSource.manual`, `MatchedBy.manual`; `SessionPainEntry` in `Pain.swift`.
- [x] 1.5 `TrainingSnapshot`: `notices`, `session(id:)`; `race(id:)` is the only race lookup.

## 2. Wire format (M)

- [x] 2.1 `HubEvent.swift`: `test.gate`, `session.done`, `session.fuel`, `race.result` (no `date`; decoded with the commands) and `pains` on `session.rpe`; `WireNumber` (a whole value as an integer, else an exact `Decimal`).
- [x] 2.2 Optional keys as `null`, except the three the vault's own lines leave out: `officialTime`, `pains` on a rating that did not ask, `during` / `after` of a site.
- [x] 2.3 Bounds in `HubEventPayload.validate` (scores on the half-step grid, minutes 1-6000, km above 0, carbs 0-2000, `h:mm:ss`, an official time never a copy, texts 1-2000); an unknown race status is an invalid line, an unknown reason or site `other`.
- [x] 2.4 Golden file `Fixtures/Events/gates.v1.app.jsonl`: the vault example's seq 25-28, 32, 33 key-sorted; the events README.

## 3. The phone's fold (M)

- [x] 3.1 `CheckInOverlay`: `gateTests`, `sessionPains` (keep / replace), `manualDone` and `retractedDone`, `fuelLogs`, `raceResults` with the vault's refusal, `liveDoneEventIDs` / `liveRaceResultEventIDs`, `pendingRaceWithdrawals`.
- [x] 3.2 `applying(to:)`: an unacknowledged `session.done` shows the session as done by hand (never a skipped or already done one; the option only when the session has it); an unacknowledged retraction shows it planned again; acknowledged, the file decides. `actual` is never touched.

## 4. View models (L)

- [x] 4.1 `GateModels.swift`: `GateCardModel` (pain mode, current day, prominent on Saturday and Sunday, the vault's verdict in words, stale, physio above two weeks, the phone's unread test, the editor and its payload), `WeekLoadModel` ("–" for unknown, warnings), `RecoveryChipModel` (reads `of`; the meaning by rule and length), `vaultNotices`.
- [x] 4.2 `TodayTrainingBuilder.today` (what describes now is built for the current day only) and the four new fields of `TodayTrainingModel`; `WeekAgendaModel.load`, `UnplannedRowModel.overPlanText`, "Done (logged by hand)" on the cards and rows.
- [x] 4.3 `SessionRecordModels.swift`: `SessionPainModel` / `SessionPainDraft` (sent with the RPE), `ManualDoneModel` (defaults from the plan, payload, undo ids), `SessionFuelModel` (when offered, the vault's numbers, the phone's unread log), `RecordInput` / `TypedNumber`.
- [x] 4.4 `SessionDetailModel`: `pain`, `manualDone`, `fuelLog`; the done card's `manualTitle` / `manualLine`; `MatchedBy.manual` in the "recognised" switch.
- [x] 4.5 `PainStepModel.settledLines` ("yesterday after the session → today", both numbers recorded, pain mode).
- [x] 4.6 `RaceResultModels.swift`: `RaceResultModel` (one record, the organiser's time first and the elapsed time second, neutral words, goal / record only on `true`, refusal, pending withdrawal) and `RaceResultEditorModel` (statuses by race day, reasons, `cleanTime`, payload); `RaceDetailModel.result`.
- [x] 4.7 Rewards: `ProjectionRewardExtras` reads `status` and `reason` (the draft's keys only when absent); `TrainingPlanFacts.raceFuelOnPlan` from the vault's fuel verdict; nothing in Gamification changes.

## 5. Strings (S)

- [x] 5.1 The new `TrainingKey` cases with English and Czech in both `Localizable.strings` and the two plural keys (`gatePhysio`, `raceLaps`) in both `.stringsdict`: every case used, none orphaned or duplicated, the same format specifiers in both languages.

## 6. App (L)

- [x] 6.1 `TrainingModel`: `recordGateTest`, `recordSessionPain`, `markDone`, `logFuel`, `recordRaceResult`, `retractEvents`; `todayBuilder` passes the current training day.
- [x] 6.2 `Training/GateAndLoadViews.swift`: `GateTestCard`, `WeekLoadLine`, `OverPlanBadge`, `RecoveryChipView`, `VaultNoticeLines`; `TrainingDayCard` (notices, recovery, the gate link or card, the load line; `onSaveGate`) and `PainStepView` (settled lines); one callback in `TodayView`.
- [x] 6.3 `Plan/WeekAgendaView`: the load line in the header, the over-plan badge on an unplanned row.
- [x] 6.4 `Plan/SessionRecordViews.swift`: `SessionPainBlock` in "How did it feel?", `ManualDoneCard` and its sheet, `FuelLogCard` and its sheet; `SessionDetailView` (the done card's manual title and line).
- [x] 6.5 `Plan/RaceResultViews.swift`: `RaceResultCard` and `RaceResultSheet`; `RaceDetailView`.

## 7. Tests (L)

- [x] 7.1 `HubEventTests`: the gates golden file byte for byte; the mirrored lines re-encoded to the same bytes and the same JSON objects; optional keys; bounds of every new payload; an unknown status / reason / site; the example decodes with the new types as payloads and folds.
- [x] 7.2 `GatesAndLoadTests` (new): decoding on both fixtures (the example, the minimal file, an older file, a data gap, unknown and broken values); the fold (gate tests, session pains, done by hand until read, its undo, skipped stays skipped, fuel logs, race results with refusal and withdrawal); the gate card; the load line and the badge; the recovery chip (14 and 7 days, an unknown rule); notices; session pain; settled lines; mark done; the fuel log; the race result and its sheet; the reward facts; typed numbers -- English and Czech.
- [x] 7.3 Goldens that change: `ProjectionDecodingTests` (`manual` is known, feedback read by field), `PlanBuilderTests` ("Done (logged by hand)", the manual record's lines).

## 8. Verification

- [x] 8.1 `openspec validate add-training-gates-and-load --strict`, `node tools/check-localizations.mjs --scan`, `sh tools/lint-design-tokens.sh`; `main` merged in and every new or changed Swift file read back for compile errors.
- [ ] 8.2 CI green on the PR (Swift compiles only there).
- [ ] 8.3 On the phone, with the vault connection on: in pain mode the gate link on a weekday and the card on a weekend, a saved test and the vault's verdict after the next sync; pain during and after sent with an RPE and "yesterday → today" the next morning; the load line on Today and in Plan with an "Over plan" badge; "Mark done (no watch)" on a gym session, its undo, and a real activity replacing it; a notice when nothing was synced; the fuel log after a long run; a race result with two times, its refusal before race day and Withdraw; the recovery chip after a race; a race reward granted once.
