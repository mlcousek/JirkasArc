## Why

The training experience still starts with opening the app. The morning
check-in has three lock-screen Controls (`add-training-checkins` D7), but
`MorningCheckInIntent` was never registered as an App Shortcut, so it
cannot be said to Siri, found in Spotlight or used in an automation, and
there is nothing for the Home Screen. A weigh-in and a glass of water each
take a screen, a sheet and a keyboard, although both are one number. And
the one figure the owner looks for most often during a season, the days to
the next race, needs the Plan tab.

All four are reachable inside the limits this account sets (no App Group,
no Keychain Sharing, no new App ID): an intent that opens the app runs in
the app's process with the app's files, and a widget can keep its own
settings in its own configuration.

## What Changes

- **The morning check-in by voice and in Shortcuts.** `MorningCheckInIntent`
  is registered in the app's `AppShortcutsProvider` with English and Czech
  phrases ("Morning check-in in Jirka's Arc", "Green / Amber / Red in
  Jirka's Arc"). The light is the phrase's parameter; without one, the
  intent asks "Green, amber or red?". It gains an optional pain score
  (0-10) and an optional pain site, sent only when a score is given, and
  answers with a confirmation that names what was recorded.
- **A Home Screen check-in widget.** Small and medium, three buttons (G
  circle, A triangle, R square). Each runs the same `openAppWhenRun`
  intent as the Controls, so the check-in is recorded by the app, with the
  app's files. The widget shows no state: it cannot read any.
- **Weight and water without a screen.** "Log weight" (kilograms, asked
  for when not given) and "Log water" (millilitres, one 250 ml glass by
  default) as App Shortcuts; a "Log water" Control that logs one glass; a
  "Log weight" Control that opens the weigh-in form. All go through
  `WeightLogCoordinator` / `HydrationLogCoordinator`: saved on the phone
  first, queued for Garmin, never waiting on the network to save.
- **A countdown widget.** Small. The event's name and date are typed into
  the widget's own configuration (Edit Widget), so it works without any
  shared storage: "Example 50K" over "120 days", with plural forms in both
  languages, "Today" on the day and "N days ago" after it.
- Three new App Shortcuts, seven in total with "Tick Habit", which
  `add-interactive-habits` registered while this change was open (the
  platform's limit is ten).

## Capabilities

### New Capabilities

None.

### Modified Capabilities

None archived. This change adds to and modifies requirements of
capabilities whose changes are not archived yet; their archive must fold
these together:

- `siri-and-shortcuts`, `lock-screen-and-controls`, `home-screen-widget`
  (from `add-glanceable-surfaces`, the last also changed by
  `add-streak-widget`);
- `training-checkins` (from `add-training-checkins`,
  `add-checkin-pain-score`, `add-daily-checkin-and-pain-mode`);
- `weight-tracking`, `hydration-tracking` (from
  `sync-weight-hydration-with-garmin`).

## Non-goals

- **A widget or Control that shows live data** (today's light, the last
  weight, the water total). It needs an App Group, which this account does
  not have; `add-glanceable-surfaces` D2 owns that decision.
- **Pain in the Controls or the widget buttons.** They stay three one-tap
  lights (`add-checkin-pain-score`, non-goals); the pain step on Today
  follows in pain mode (`add-daily-checkin-and-pain-mode`).
- **Ticking habits by voice or from a widget.** Owned by
  `add-interactive-habits` (its own `TickHabitIntent` and App Shortcut,
  merged meanwhile; three of the ten are left).
- **A race countdown fed by the plan.** The widget cannot read the plan;
  the in-app countdown is `add-season-phase-race-screens`.
- **A water amount chosen per Control**, a weight Control that records a
  number by itself, Lock Screen (accessory) families for the two new
  widgets, and a Live Activity. Possible follow-ups, not built here.
- **Any new Garmin route.** The two write routes used are the ones the
  weight and water screens already use.

## Impact

- `Shared/` (both targets): `MorningCheckInIntents.swift` (parameters, the
  request the app's hook receives, the confirmation), new
  `QuickHealthLogIntents.swift` (the shared weight and water action, the
  water Control's intent, the weigh-in form intent),
  `AppNavigationBridge.swift` (one new route).
- App: `Shortcuts/GarminFoodShortcuts.swift` (three shortcuts), new
  `Shortcuts/LogWeightAndWaterIntents.swift` (`LogWeightIntent`,
  `LogWaterIntent`), `GarminFoodApp.swift` and
  `Training/TrainingEventsService.swift` (the hook's new shape), new
  `App/AppEnvironment+QuickHealthLog.swift` and one line in
  `App/AppEnvironment.swift` (refresh after a screenless log),
  `App/AppRouter.swift` and `ContentView.swift` (the
  weigh-in form opened by its Control), `Localizable.xcstrings`,
  `AppShortcuts.xcstrings`.
- Widget extension: new `MorningCheckInWidget.swift`,
  `CountdownWidget.swift`, `Controls/QuickHealthControls.swift`;
  `GarminFoodWidgetBundle.swift`; `WidgetTheme.swift` (the palette's
  colour scheme, for a theme with one scheme);
  the widget's `Localizable.xcstrings`.
- FoodLogCore: new `QuickHealthLog.swift` (what a screenless weigh-in or
  drink may record, and what happened to it), `EventCountdown.swift`,
  `BoundedWait.swift`, with tests.
- TrainingCore: new `Events/QuickCheckIn.swift` (a check-in with one pain
  number), with tests.
- `project.yml`: unchanged. Sources are path-globbed and no target,
  entitlement or App ID is added.
- Nothing is persisted in a new file (no `StoreCatalog` entry).
- Not verified here: Swift compiles only in CI; everything a device must
  confirm is listed in `tasks.md` section 7.

**Depends on**: `add-glanceable-surfaces` (the widget extension, Controls,
App Shortcuts), `add-training-checkins` (the check-in intent, its hook and
the recorder), `add-checkin-pain-score` and
`add-daily-checkin-and-pain-mode` (pain on the check-in, pain mode),
`sync-weight-hydration-with-garmin` and `fix-review-findings-2026-09` (the
weight and water coordinators and outboxes), `add-themes-and-layout` (the
per-widget theme).

**Unblocks**: nothing planned. A later App Group (a paid account) could
give both widgets live content without changing these intents.
