Every task ends with CI green: `swift test` for FoodLogCore and
TrainingCore, the design-token lint, the app and widget `xcodebuild`, and
the `localization` job. Every new `.swift` file starts with a header
comment saying why it exists and what depends on it. All new user-facing
text is in English and Czech. **Nothing personal in the repository**: test
data is synthetic (the vault example's 2030 season, round numbers), and no
event name, date, weight, token or repository name is written into code,
strings, fixtures or docs. No new Garmin route, no new stored file (no
`StoreCatalog` entry), no new target, entitlement or App ID. Branch
`mlcousek/training-shortcuts-and-widgets` on `main`. Relative size:
S / M / L.

A box is ticked when the code was written and read back against its call
sites and tests; nothing here was compiled locally (no Swift toolchain),
so sections 6.3 and 7 stay open until CI and the phone have said so.

## 1. Pure rules in the packages (M)

- [x] 1.1 FoodLogCore `QuickHealthLog.swift`: `QuickLogInput` (weight above 0 and below 500 kg, water above 0 and below 5000 ml, the 250 ml default glass), `QuickHealthLog` (validate, then commit through the coordinator), `QuickLogDelivery` (what a bounded drain says happened).
- [x] 1.2 FoodLogCore `BoundedWait.swift`: wait for an operation at most N seconds without cancelling it.
- [x] 1.3 FoodLogCore `EventCountdown.swift`: whole calendar days to an event (`upcoming` / `today` / `past`), the next midnights, the cleaned event name.
- [x] 1.4 TrainingCore `Events/QuickCheckIn.swift`: the score rule (0...10 or refused, nearest half step), the default site, the check-in payload with and without a score.
- [x] 1.5 Tests: `QuickHealthLogTests` (real stores on temp files: a refused number writes nothing; Garmin mode queues, standalone does not), `BoundedWaitTests`, `EventCountdownTests` (a DST night, the year boundary, past and today), `QuickCheckInTests` (the vault example: day, session, default site from history, out of range, half step, no score keeps `pains` nil).

## 2. The check-in intent and its App Shortcut (M)

- [x] 2.1 `Shared/MorningCheckInIntents.swift`: `CheckInPainSiteOption`, `MorningCheckInRequest` / `MorningCheckInReceipt`, the handler's new shape, `painScore` and `painSite`, the light's `requestValueDialog`, `init()` without a preset light, the parameter summary, the confirmation dialog, the out-of-range error (no `inclusiveRange`, so the refusal is the app's own sentence).
- [x] 2.2 `TrainingEventsService.handleCheckIn(_:)` (through `CheckInPlanning`, the phone's overlay for the default site, Today brought forward only without a score); `GarminFoodApp.init()` installs it.
- [x] 2.3 `GarminFoodShortcuts`: the check-in shortcut ("Morning check-in in ...", "<light> in ...", "Check in <light> in ..."); header updated (seven of ten: the habits shortcut landed on `main` meanwhile).

## 3. Weight and water (M)

- [x] 3.1 `Shared/QuickHealthLogIntents.swift`: `QuickHealthLogAction` (validate, commit, bounded delivery, the `onLogged` hook, localized errors), `LogWaterGlassIntent` (Control), `OpenWeighInIntent` (Control).
- [x] 3.2 App target `Shortcuts/LogWeightAndWaterIntents.swift` (`LogWeightIntent`, `LogWaterIntent`, one file) with spoken answers; their two App Shortcuts.
- [x] 3.3 `AppEnvironment` (`App/AppEnvironment+QuickHealthLog.swift`, one line in `init`): `QuickHealthLogAction.onLogged` -> `weightLogged()` / `hydrationLogged()`.
- [x] 3.4 The weigh-in form from its Control: `AppNavigationBridge` route `.weighIn`, `AppRouter.weighInRequested`, the sheet on `ContentView`.
- [x] 3.5 `Controls/QuickHealthControls.swift`: `LogWaterControl`, `LogWeightControl`; registered in the bundle.

## 4. Widgets (M)

- [x] 4.1 `MorningCheckInWidget.swift`: small and medium, three `Button(intent:)`, letter and shape and colour, themed, VoiceOver labels and hints, previews.
- [x] 4.2 `CountdownWidget.swift`: `CountdownWidgetIntent` (name, date, theme), the midnight timeline, the three states and the unconfigured state, plural day counts, previews.
- [x] 4.3 `WidgetTheme.swift`: the palette's colour scheme for a single-scheme theme; `GarminFoodWidgetBundle`: both widgets and both Controls.

## 5. Strings (S)

- [x] 5.1 App `Localizable.xcstrings`: every new key with Czech (text insertion, CRLF, no JSON round-trip).
- [x] 5.2 Widget `Localizable.xcstrings`: the widget's keys and every `Shared/` key, with Czech; plural variations for "%lld days" and "%lld days ago".
- [x] 5.3 `AppShortcuts.xcstrings`: the seven new phrases with Czech, `${applicationName}` and `${light}` verbatim.

## 6. Checks (S)

- [x] 6.1 `node tools/check-localizations.mjs --scan`, `sh tools/lint-design-tokens.sh`, `npx openspec validate add-training-shortcuts-and-widgets --strict`.
- [x] 6.2 Docs: `CLAUDE.md` (the widget extension is no longer "static only"; the new Shared file), this change's design kept as built.
- [ ] 6.3 **Requires CI.** `swift test` for FoodLogCore and TrainingCore and the app and widget `xcodebuild` are green; the localization export comparison passes. The signatures written from memory (design, Risks) are the first thing to read in a red log.

## 7. On the phone (not verifiable here)

- [ ] 7.1 The check-in widget's buttons open the app and record the light; with the connection off the failure is shown and nothing is recorded.
- [ ] 7.2 "Green in Jirka's Arc" and "Morning check-in in Jirka's Arc" (asks for the light); whether a locked phone asks to unlock, and whether the confirmation is spoken or shown. If the unlock is in the way at 4:00, build the background sibling intent (design D1).
- [ ] 7.3 A shortcut with a pain score: the event carries it, Today shows it in pain mode, a score above 0 turns pain mode on.
- [ ] 7.4 "Log weight in Jirka's Arc" asks for the number, the weigh-in reaches Garmin; "Log water in Jirka's Arc" and the water Control add 250 ml; the cards update when the app is open.
- [ ] 7.5 The weight Control opens the form with the keyboard up, from any tab.
- [ ] 7.6 The countdown widget: Edit Widget offers the name, a date-only picker and the theme; the count is right and changes overnight; Czech plurals.

## 8. Review fixes (2026-10-07, branch `mlcousek/shortcuts-review-fixes`)

Four findings of the review of the merged change. Same rules: nothing
compiled locally, strings inserted as text in both languages.

- [x] 8.1 A pain site without a pain score is refused, not dropped: `QuickPainAnswer.given(score:site:)`, `ActionError.painSiteNeedsScore`, its sentence in both catalogs, tests.
- [x] 8.2 A repeated check-in is not a second event: `CheckInPlanning.quickCheckIn` and `QuickCheckInDecision` (same light without a score: nothing recorded; with a score: the earlier session and option kept; another light: a new choice), `CheckInOverlay.checkInOptions`, the receipt's `alreadyRecorded` and "Check-in already recorded: ...", tests.
- [x] 8.3 A widget tap that recorded nothing is said by the app once: `MorningCheckInWidgetIntent` (never throws, not discoverable), `AppNavigationBridge.pendingNotice`, the alert on `ContentView`, `ActionError.notSaved`.
- [x] 8.4 The weight Control's request is dropped when the form can't be presented now (onboarding, the theme preview, the alert): `AppRouter.applyPendingRoute(weighInBlocked:)`.
- [x] 8.5 design.md (D1 to D4, D6, Risks incl. the countdown's time-zone limit), the three spec deltas and CLAUDE.md as built; the four checks.
- [ ] 8.6 **Requires CI.** `swift test` for TrainingCore, the app and widget `xcodebuild`, the localization export comparison.

On the phone, with section 7:

- [ ] 8.7 Vault connection off, tap the check-in widget: the app opens and shows "Nothing recorded: turn on the vault connection ..." once; a Control with the connection off shows its own failure and the app shows no alert.
- [ ] 8.8 Tap Amber on the widget twice: one event in Settings > Vault's pending writes; the amber Control afterwards answers "already recorded".
- [ ] 8.9 On a fresh install still in onboarding, the weight Control opens the app and no weigh-in form appears after onboarding.
- [ ] 8.10 A shortcut with a pain site and no score answers that the score is needed and records nothing.
