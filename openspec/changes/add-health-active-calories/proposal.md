## Why

The partner's install runs standalone: no Garmin, so there is no "Active
today" line and no active-calorie goal. She wears an Apple Watch, and her
phone's Apple Health has the whole day's **active energy** (workouts and
everyday movement). The owner wants exactly that one number in the app,
and nothing else from Health (decision 2026-10-19).

HealthKit is **not available on a free Personal Team** (`openspec/config.yaml`,
hard constraints, 2026-09-14), and the owner keeps development free. So
the number comes in the free way: a **Shortcuts automation** on her phone
reads today's Active Energy from Health and hands it to an App Intent of
this app. Shortcuts holds the Health permission, so the app needs no
entitlement. When that isn't set up, she types her activities into the
app by hand.

## What Changes

- **Active calories per day, stored on the phone** (FoodLogCore, pure):
  one Health value per day plus any manual activities.
- **The Health bridge.** An App Intent, "Zapsat aktivní kalorie ze Zdraví",
  takes a day and its Active Energy total and runs without opening the
  app. Settings > Aktivita offers "Přidat zkratku" (an iCloud shortcut
  link) and a 3-step guide to make it a personal automation that runs
  several times a day, "Run immediately". A spike first proves that
  Shortcuts reads Active Energy on iOS 26.
- **Manual activities.** "Přidat aktivitu" on Today: type (Běh, Chůze,
  Kolo, Plavání, Posilovna, Jóga, Jiné), minutes and kcal.
- **One rule for the day's total.** A Health report for the day wins.
  Without one, the total is the sum of the manual activities. Manual
  entries stay listed either way, so nothing is counted twice.
- **Standalone gets the activity surfaces a Garmin install has**: the
  "Active today" line and the active-calorie goal
  (`MealDashboard.build(activeKilocalories:)` already takes the value).
  Garmin-connected installs are unchanged, with Garmin as their source.

## Capabilities

### New Capabilities

- `active-calories`: the per-day store, the Health bridge, manual
  activities, the total rule, what standalone shows.

### Modified Capabilities

- None. Garmin-connected behaviour and `data-mode`'s standalone rules are
  unchanged. Standalone gains a non-Garmin source of active calories.

## Non-goals

- **Strava.** With an Apple Watch, Health's Active Energy already includes
  every workout Strava shows, plus the rest of the day. Adding Strava's
  per-activity calories would count workouts twice. Strava would also need
  her own Strava API application with its secret on the phone. If she
  ever stops wearing the watch, a separate change can add it.
- Steps, exercise minutes, workouts, heart rate, sleep or anything else
  from Health (owner decision 2026-10-19: active calories only).
- Writing food or anything else into Health.
- Native HealthKit (needs the paid program; the owner stays free).
- A widget (no App Groups on the free tier).

## Impact

- **Depends on**: `add-standalone-mode` (archived),
  `add-training-shortcuts-and-widgets` (App Intents infrastructure).
- **Unblocks**: the "Ohnivá vůle" partner achievement in
  `add-partner-love-theme`.
- No entitlement, no target, no background mode. One App Intent, one
  Settings screen, one Today row, one store `activity/days.json` (in
  backups).
