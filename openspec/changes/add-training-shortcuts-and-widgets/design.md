## Context

Written 2026-10-02 on `mlcousek/training-shortcuts-and-widgets`, on `main`
after PR #126 (`add-daily-checkin-and-pain-mode`). Finished 2026-10-06
after `main` gained #127 (`add-interactive-habits`, which registered a
fourth App Shortcut, "Tick Habit") and #128 (`add-training-gates-and-load`);
every call into TrainingCore was read again against those declarations,
and the counts below are the ones after that merge. This document is kept
as built.

What the code already provided when this was written:

- `Shared/MorningCheckInIntents.swift`: `MorningCheckInIntent(light:)`,
  `openAppWhenRun`, `.alwaysAllowed`. `Shared/` is compiled into the app
  and the widget extension; the widget links GarminKit, FoodLogCore and
  AppearanceKit, never VaultKit or TrainingCore. So the intent calls a
  hook, `MorningCheckInControlAction.handler`, which `GarminFoodApp.init()`
  points at `TrainingEventsService` before any scene exists
  (`add-training-checkins` D7). Three Controls use it; no App Shortcut.
- `GarminFoodShortcuts`: three App Shortcuts (usual food, food by name,
  barcode scanner), four since #127 (tick a habit). Apple's compile-time
  limit is ten.
- Two kinds of logging intent (`add-glanceable-surfaces` D1, D5): the
  Controls' intents in `Shared/` open the app (`openAppWhenRun`), because
  the extension process has no credential and no files; the Siri intents
  in the app target (`LogTopQuickPickIntent`, `LogNamedFoodIntent`) run in
  the app's process without bringing it forward and answer with a dialog.
- `WeightLogCoordinator.logWeight` and `HydrationLogCoordinator
  .logHydration`: the local record first, then the outbox entry under an
  id chosen up front, no network (`fix-review-findings-2026-09` finding
  4). In standalone mode nothing is queued. `AppServices` holds the one
  instance of each per process.
- `ConfirmedLogRelay` (`fix-review-findings-2026-09` finding 1) hands a
  screenless *food* log to the gamification award exactly once.
- Widgets: `AppIntentConfiguration` with `WidgetThemeIntent`
  (`add-themes-and-layout` D13): a widget's own settings are stored by
  WidgetKit with the widget and handed to the extension's provider. No
  App Group is involved.

What was probed: nothing. This change adds no Garmin route and no vault
contract field. The two write routes it reaches are the ones the screens
already use: `POST /weight-service/user-weight` (live-confirmed
2026-09-23, 204) and `POST /usersummary-service/usersummary/hydration/log`
(device logs observed arriving 2026-09-23). `checkin.morning` with `pains`
is the vault's contract of 2026-09-30, already golden-tested.

No Swift toolchain here: correctness rests on the package tests and the
`xcodebuild` in CI, and on a phone for everything in tasks.md section 7.

## Goals / Non-Goals

**Goals**

- The check-in from Siri, Spotlight, the Shortcuts app and the Home
  Screen, recorded by the same code as the Controls and Today.
- A weigh-in and a drink in one sentence or one tap, through the existing
  local-first path.
- A countdown that needs nothing from the app.
- Every rule that can be wrong without a compiler lives in a package and
  is tested there.

**Non-goals**: see proposal.md.

## Decisions

### D1 -- One check-in intent for every surface

`MorningCheckInIntent` stays the only check-in intent. The Controls, the
new widget's buttons and the App Shortcut all use it, so there is one
place that records and one set of failure messages.

- `light` keeps its type (`CheckInLightOption`, an `AppEnum`, which is
  what a phrase parameter must be). `init()` no longer presets green: a
  run without a light ("Morning check-in in Jirka's Arc") must ask, and
  `requestValueDialog` words the question ("Green, amber or red?"). The
  Controls and the widget still pass the light (`init(light:)`).
- New optional parameters: `painScore: Double?` (0...10) and `painSite:
  CheckInPainSiteOption?` (an `AppEnum` whose raw values are the
  contract's site words; the fifth reads "Other site", the pain step's
  wording). Neither is ever asked for. They are for the Shortcuts app and
  automations; a phrase can carry one parameter only. The score declares
  no `inclusiveRange`: a 12 must reach `perform()`, so the refusal is the
  app's own sentence and the rule stays in one tested place (D3).
- `perform()` returns a dialog: "Check-in recorded: Amber." or
  "Check-in recorded: Amber. Pain 4.5/10, Achilles (left)." A label and a
  value, not a sentence glued from fragments; the light and site names
  are the catalog's own.
- `openAppWhenRun` stays `true`. It is what makes the Controls and the
  widget buttons work, and one type cannot have it both ways. So a
  check-in said to Siri opens the app too. In pain mode that is where
  the pain step waits anyway.

*Alternative considered:* a second, app-only intent for Siri that records
in the background without opening the app (the shape of
`LogTopQuickPickIntent`). Refused for now: two check-in intents to keep
identical, for a gain only a phone can measure (does a locked phone ask
for Face ID at 4:00?). It is the named follow-up if it does (tasks 7.2).

### D2 -- The hook carries a request and returns a receipt

`MorningCheckInControlAction.handler` becomes
`(MorningCheckInRequest) async throws -> MorningCheckInReceipt`. The
request is plain values (`light`, `painScore?`, `painSite?` as the
contract's words), because `Shared/` cannot name TrainingCore's types.
The receipt says which pain entry was recorded (site and score after the
rules of D3), so the dialog reads back what is in the event, not what was
asked; or it says `alreadyRecorded`, when the request was a repeat of the
day's light and nothing new was written ("Check-in already recorded:
Amber."). `TrainingEventsService.handleCheckIn` is the one implementation;
the connection guards are unchanged (off, not configured, standalone, no
device id: nothing recorded, a message that says why).

### D3 -- A check-in with one pain number (`QuickCheckIn.swift`)

Pure, in TrainingCore, tested there:

- The score must be finite and within 0...10, else the check-in is
  refused whole (`painScoreOutOfRange`): clamping 12 to 10 would record a
  pain nobody reported. Inside the range it is rounded to the nearest
  half step (4.3 -> 4.5), which is the contract's grid and what the
  slider on Today does (`PainDraft.rounded`).
- The site, when not given, is the first site the pain step would offer:
  the Achilles site of the latest earlier day that scored one (the vault's
  days with the phone's own answers laid over), else the fallback site
  (`PainDraft.defaultSites`, unchanged). The dialog names it.
- The event is `checkin.morning` with `pains: [{site, score}]`. By the
  contract a check-in with `pains` **replaces** the day's answer, so a
  morning with two scored sites becomes one site when re-sent this way.
  Accepted and stated; Today's pain step is still the way to score more
  than one site.
- Without a score `pains` is not sent (`null`), which keeps the day's
  earlier answer: the Controls' rule (`add-checkin-pain-score` D7).
- A site WITHOUT a score is refused whole (`QuickPainAnswer.given`,
  `painSiteWithoutScore`; the answer is "Nothing recorded: a pain site
  needs a pain score. ..."). The first build dropped the site and
  answered "recorded" (review of 2026-10-06): a confirmation must never
  cover something that was ignored.
- A score is recorded whenever it is given, in or out of pain mode. Like
  "Something hurts?", a score above 0 turns the phone's half of pain mode
  on by itself (`PainModeState`, derived from the event log).
- After a check-in without a score the app still brings Today forward in
  pain mode (`onControlCheckIn`); with a score it does not, because the
  question is answered.
- **A repeat is not a second event** (`CheckInPlanning.quickCheckIn`,
  added after the review of 2026-10-06). The vault takes the LAST
  `checkin.morning` of a day for its light, session and option (only
  `pains` survives from an earlier event), and this path builds session
  and option from today's cached plan and the light's own letter. So,
  against the phone's own check-in of that training day (`CheckInOverlay`,
  which now also keeps the option an event named): the same light without
  a score records nothing and the receipt says "already recorded"; the
  same light with a score is recorded with the EARLIER session and option
  and the new pain entry; another light, or no check-in of this phone for
  the day, is recorded as a new choice. No contract change. Two limits,
  stated: a check-in only the vault knows (another install) is not seen,
  and no screen of this app records a check-in whose option differs from
  its light's letter today -- so what the rule prevents in practice is
  the duplicate event and a session or option rebuilt from a plan that
  changed since the first tap; the carried option is there for the day a
  screen does offer that choice.

### D4 -- The check-in widget

`MorningCheckInWidget`, kind `com.mlcousek.garminfood.widget.checkin`,
`systemSmall` and `systemMedium`, in the existing extension.

- Three `Button(intent: MorningCheckInIntent(light:))`. Interactive
  widgets are iOS 17, the deployment target. A button's intent runs where
  the intent says: `openAppWhenRun` brings the app forward and `perform()`
  runs there, exactly as for a Control. Nothing is shared and nothing is
  stored by the widget.
- **It shows no state.** Not the chosen light, not "done": the extension
  cannot read the app's files, and a guess would be worse than nothing
  (`add-glanceable-surfaces` D2). The buttons look the same before and
  after; the app that opens is the confirmation.
- Letter and shape as well as colour, as on Today and the Controls: G
  circle, A triangle, R square, in the theme's `success`, `warning` and
  `danger`, on the theme's `surface` over its `background`. The medium
  size adds the colour's word. Each button has a VoiceOver label and
  hint.
- Themed like the other widgets: `AppIntentConfiguration` with
  `WidgetThemeIntent`, colours from AppearanceKit. A theme with one
  scheme (a dark-only theme in light mode) sets the view's colour scheme
  to the palette's, so the system text styles stay readable on it.
- Timeline: one entry, `.never`.

### D5 -- Weight and water: one action, two kinds of intent

`Shared/QuickHealthLogIntents.swift` holds `QuickHealthLogAction`
(`logWeight(kg:)`, `logWater(amountML:)`), used by:

- the App Shortcuts' intents in the app target (`LogWeightIntent`,
  `LogWaterIntent`, both in `Shortcuts/LogWeightAndWaterIntents.swift`):
  no `openAppWhenRun`, a spoken answer -- the shape of
  `LogTopQuickPickIntent`;
- the water Control's intent in `Shared/` (`LogWaterGlassIntent`):
  `openAppWhenRun`, `.alwaysAllowed` -- the shape of the quick-pick
  Controls.

The action:

1. checks the number (`QuickLogInput`, FoodLogCore, pure): weight above 0
   and below 500 kg, water above 0 and below 5000 ml -- the bounds of
   `AddWeightSheet` and `AddHydrationSheet`; no amount means one glass,
   250 ml (the Water screen's middle preset). A refused number records
   nothing;
2. commits through the coordinator (`QuickHealthLog`, FoodLogCore, tested
   with real stores): durable on return, no network;
3. in Garmin mode waits at most two seconds for that outbox to drain
   (`BoundedWait`; the drain is never cancelled), so the answer can say
   "Logged to Garmin", "will sync" or "sign in again". Standalone mode
   skips this (`ShortcutLoggingRules.waitsForGarminDelivery`). An expired
   sign-in is a thrown error for the Control and a plain sentence for
   Siri: loud either way, and the entry is saved either way;
4. tells the running app (`QuickHealthLogAction.onLogged`, set by
   `AppEnvironment` in `App/AppEnvironment+QuickHealthLog.swift`), which
   reloads the weight or water card and the sync queue count. If the app's environment does not exist yet (a cold
   launch by the intent), there is nothing to refresh: the first
   foreground reads the stores.

**No relay.** `ConfirmedLogRelay` exists because a food log earns an
award that only the app's gamification engine can give, exactly once. A
weigh-in or a drink earns none in the app either (`weightLogged()` and
`hydrationLogged()` only refresh and drain); the signals built from them
are recomputed from the stores. So a hook that may be missing is enough,
and nothing is held.

Parameters: `weightKg: Double` (no default: Siri asks "What do you weigh,
in kilograms?"), `amountML: Int` (default 250). Neither declares an
`inclusiveRange`: a number `QuickLogInput` refuses reaches `perform()` and
is answered with "Nothing saved: the weight must be above 0 and below 500
kg." (or the amount's sentence), not with the system's. Neither can be an
App Shortcut phrase parameter (a phrase parameter must be an `AppEnum` or
`AppEntity`), so the phrases are fixed: "Log weight in ...", "Log water
in ...".

### D6 -- The weight Control opens the form

A Control is one tap and cannot take a number, and the weight changes
every day. So "Log Weight" opens the app with the weigh-in form up
(`OpenWeighInIntent` -> `AppNavigationBridge` route `.weighIn` ->
`AppRouter.weighInRequested` -> a sheet on the root view). Stated as what
it is: two taps and the digits. The one-tap paths are Siri and a
Shortcuts automation with the number in it.

### D7 -- The countdown widget

`CountdownWidget`, kind `com.mlcousek.garminfood.widget.countdown`,
`systemSmall`.

- `CountdownWidgetIntent: WidgetConfigurationIntent` with `eventName:
  String?`, `eventDate: Date?` (a date, no time) and `theme`. WidgetKit
  stores them with the widget instance and gives them to the extension's
  provider: no App Group, no file, nothing read from the app. The name
  and date exist only on the phone; none is in the code.
- Not set yet: "Countdown" and "Edit the widget to choose an event". No
  default event, and no sample one in the widget gallery either (the
  snapshot is the unconfigured tile): a just-added widget must never show
  a number nobody typed.
- `EventCountdown` (FoodLogCore, pure, tested): whole calendar days from
  today to the event's day in the device's calendar -- `upcoming(days)`,
  `today`, `past(days)` -- and the next midnights. A day is a calendar
  day, so a DST change is not a day more or less.
- The timeline has an entry for now and for each of the next seven
  midnights, policy `.atEnd`: the number changes at midnight without the
  app, and WidgetKit asks again about once a week.
- Text: "%lld days" and "%lld days ago" are plural keys in the widget's
  catalog (Czech one / few / many / other), "Today" on the day. The
  event's name is shown as typed, trimmed and cut to 40 characters.
- It lives in FoodLogCore because that is the tested package the widget
  already links; TrainingCore is app-only.

### D8 -- App Shortcuts: seven of ten

New: Morning Check-in, Log Weight, Log Water. With the three first ones
and Tick Habit (`add-interactive-habits`, merged while this change was
open) that is seven. `add-glanceable-surfaces` asked for "no more than 5";
that requirement is changed to the platform's ten, with the reason: the
training experience added actions worth saying. Three stay free. Every
phrase contains `\(.applicationName)`; the Czech phrases are in
`AppShortcuts.xcstrings` under the English key with `${applicationName}`
and `${light}`.

The two new Controls are listed in a second `if #available(iOS 18.0, *)`
block of `GarminFoodWidgetBundle`: the first block already holds eight
Controls, and a result-builder block takes a limited number of entries.

### D9 -- Strings

App and widget strings are text insertions into the two
`Localizable.xcstrings` catalogs (CRLF kept, never a JSON round-trip:
the app catalog has duplicate keys). Everything used in `Shared/` is in
both. Czech in the informal register, the vocabulary already in the
catalogs ("Ranní kontrola", "Zelená", "Oranžová", "Červená", "Achilovka
(levá)"). The Siri answers for weight and water reuse the existing
"Saved %@ ..." / "Logged %@ to Garmin." keys with the amount ("75.5 kg",
"250 ml") in place of the food's name.

## Risks / Trade-offs

- **Not compiled here.** App Intents signatures with no earlier use in
  this repository, written from memory: `requestValueDialog:` on
  `@Parameter` (an `AppEnum` and a `Double`), `kind: .date` on a `Date?`
  parameter, the `Summary { }` builder with extra parameters, a parameter
  in an `AppShortcutPhrase` (`\(\.$light)`), `Button(intent:)` in a
  widget. CI's `xcodebuild` is the check; each has a plainer fallback
  (drop the argument, or the whole `parameterSummary`) that keeps the
  feature. `inclusiveRange:` was in the first draft and is gone: it was
  one more unverified signature, and it would have answered a refused
  number with the system's words instead of the app's.
- **A widget button with `openAppWhenRun`** is expected to open the app
  and run there, as a Control's does. Unconfirmed on a phone. Fallback:
  give each button a `Link` to a `garminfood://checkin?light=` URL that
  the app handles (one more deep-link action).
- **A Siri check-in opens the app** (D1) and, on a locked phone, may ask
  to unlock, as the Controls may. Follow-up named in D1.
- **Whether the dialog is spoken once the app comes forward** is the
  system's choice. The app showing the chosen light is the visible
  confirmation.
- **A single pain number replaces a two-site answer** (D3). Stated in the
  parameter's description.
- **"Green in Jirka's Arc" is a short phrase.** If Siri does not catch
  it, "Check in green in Jirka's Arc" is registered too.
- **Siri does not speak Czech.** The Czech phrases serve Spotlight and the
  Shortcuts app on a Czech phone; voice use is in English.
- **A water Control tapped twice logs two glasses.** That is the
  feature; removing a drink is one swipe on the Water screen.
- **`.alwaysAllowed` on the water Control** means anyone holding the
  phone can add a glass. Same accepted risk as the quick picks.

## Migration Plan

None. No stored data changes shape. A placed Control keeps its kind. An
existing shortcut that used "Morning Check-in" without choosing a light
(there cannot be one: the intent was not exposed to Shortcuts before)
would now be asked.

## Open Questions

- Should the water Control's glass size be chosen per Control
  (`AppIntentControlConfiguration`)? Left out: one more unverified API
  for a value the Shortcuts app can already set.
- Should the countdown also come as a Lock Screen accessory ("Example 50K · 120
  days" inline)? Cheap once the small one is confirmed on a phone.
