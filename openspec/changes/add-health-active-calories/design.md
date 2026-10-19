## Context

Written 2026-10-19 on `main` at `43b1db0`, before any code.

Owner decisions (2026-10-19):

- she has an Apple Watch;
- Health is used for active calories only;
- she also uses Strava Basic, but manual tracking in the app is fine if
  Strava is a problem;
- development stays free.

What exists:

- `MealDashboard.build(activeKilocalories:)` and `ActiveCalorieGoal`
  (FoodLogCore). `DayLogLoader` feeds them from Garmin's daily summary on a
  connected install and hides the line in standalone (`data-mode`).
- App Intents (`add-training-shortcuts-and-widgets`):
  `Shared/QuickHealthLogIntents.swift` already records a weigh-in or a
  drink without a screen, with the pure rules in FoodLogCore
  `QuickHealthLog`.
- No HealthKit on the free team (config.yaml, 2026-09-14).

## Decisions

### D1: Health through Shortcuts, not Strava

Strava Basic does not block its API: the API is open to free accounts as
far as known; task 1.2 checks this. But Strava is the wrong source here:

- Her Apple Watch writes Active Energy for the **whole day** into Health.
  That already includes every workout she also uploads to Strava.
- Strava's calories are per activity, so they are a subset of that total.
  Using both would count workouts twice. Using Strava alone would miss
  the rest of the day.
- Strava needs an OAuth app registered by her, a client secret typed into
  the phone, and token refresh: more moving parts than a shortcut.

So Health is the source, through Shortcuts, and manual entry is the
fallback. Strava is a non-goal.

### D2: The store and the total rule

`ActiveCaloriesDay` (FoodLogCore `Activity/`) holds:

- `date`;
- `health: { kcal, reportedAt }?`, the latest bridge report;
- `manual: [ManualActivity]`, each with `id`, `type`, `minutes?`, `kcal`
  and `createdAt`.

It lives in the store `activity/days.json`, which keeps the last 400 days
and is included in backups.

- A newer Health report for a day **replaces** the older one. Health's
  daily total only grows, so a later read is the truth.
- The day's total is `health.kcal` when present, otherwise the sum of the
  manual activities. Today names which one it shows ("ze Zdraví" /
  "ručně").
- A report dated more than 7 days ago, or in the future, changes nothing.
- A negative or absurd value (> 10 000 kcal) is refused.

Nothing awaits the bridge on a screen path. Today renders from the store.

### D3: The Shortcuts bridge

**Spike first (task 1.1).** On iOS 26, with an Apple Watch, check that this
returns the same number as the Health app's Active Energy for today:

1. Find Health Samples, Type Active Energy, Start Date is today;
2. Calculate Statistics, Sum.

Also check the number's formatting under the Czech locale, and that a
time-of-day personal automation runs with "Run immediately" without
asking. Record the iOS build, the date and the results in this file under
"Probed".

**The intent.** `RecordActiveCaloriesIntent` ("Zapsat aktivní kalorie ze
Zdraví") takes the parameters `date` (default today) and `kcal` (text,
accepting a decimal comma or point). It runs with `openAppWhenRun =
false`. The pure parsing lives in FoodLogCore `ActiveCaloriesIntake`.

**The shortcut** is built once by the owner and shared as an iCloud link.
The link is not personal and is shown in Settings > Aktivita with the
guide:

1. Add the shortcut.
2. Create a personal automation: Time of day, at 10:00, 14:00, 18:00 and
   21:30 (four automations, or one that repeats hourly).
3. Turn on "Run immediately".

Settings shows the last report time. When the bridge has reported before
and nothing has arrived for 2 days, Today shows a quiet "Zdraví se 2 dny
neozvalo" row with the guide. A silent bridge is the closest thing to an
auth failure here, so it is made visible.

**Freshness.** The value is as fresh as the last automation run. Opening
the app does not read Health; the app can't. The guide suggests one more
automation, "When the app Jirka's Arc is opened": it runs the shortcut, so
Today is current whenever she opens it.

### D4: Manual activities

"Přidat aktivitu" on Today (standalone) opens a small sheet: type chips,
minutes (optional) and kcal (required, 1–3 000). Entries can be edited and
deleted. With a Health report for the day they stay listed but greyed,
with "Zdraví už je započítává", so a workout the watch also saw is not
added twice.

### D5: What standalone shows

With a total for the day:

- the summary card shows "Aktivní dnes: 420 kcal (ze Zdraví)";
- the active-calorie goal behaves as on a Garmin install;
- the partner theme's "Ohnivá vůle" achievement can count the day.

Without any source, standalone is exactly as today.

## Probed

Nothing yet. Task 1.1 (Shortcuts and Active Energy on iOS 26) and task 1.2
(Strava API with a Basic account, for the record only) fill this section.

## Risks / Trade-offs

- **The automation can be switched off** by her or by an iOS update. The
  2-day row makes that visible.
- **Shortcuts behaviour may change** in a future iOS. The fallback is
  manual entry, and later the paid program.
- **Health totals lag the watch** by its sync delay (usually minutes). The
  next automation run catches up.

## Migration Plan

None. With no report and no manual entry, nothing changes.

## Open Questions

None open. The owner's answers of 2026-10-19 settle the scope.
