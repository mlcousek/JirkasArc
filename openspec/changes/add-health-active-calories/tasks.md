Every task ends with CI green (`swift test` for FoodLogCore, the app and
widget `xcodebuild`, `localization`). All new user-facing text is in
English and Czech. Nothing personal in the repository: test activity is
synthetic (dates in 2030). No entitlement, target or background mode.
Branch `mlcousek/partner-love-theme` (built together with the partner
theme). Relative size: S / M / L.

Nothing here was compiled locally (no Swift toolchain); CI is the check.

## 1. Probe (S)

- [ ] 1.1 Spike on her iPhone (iOS 26, Apple Watch paired): Find Health Samples (Active Energy, today) and Calculate Statistics (Sum) match the Health app's value; the number format under the Czech locale; a time-of-day automation with "Run immediately" runs unasked; an "app opened" automation runs. Record the iOS build, the date and the results in design.md "Probed". **Waits for the phone test.**
- [ ] 1.2 For the record: does Strava's API answer for a Basic account? Nothing is built on it (D1). Optional.
- [x] 1.3 `openspec validate add-health-active-calories --strict`.

## 2. Pure rules (S)

- [x] 2.1 FoodLogCore `Activity/ActiveCalories.swift`: `ActiveCaloriesDay` (Health value replaced by newer, manual list, the total rule), `ActiveCaloriesRules` (7-day and future guards, 0–10 000 kcal, manual 1–3 000 kcal), `ActiveCaloriesStore` (`active-calories.json`, 400 days, in backups via `StoreCatalog` `foodlog.active-calories`).
- [x] 2.2 `ActiveCaloriesIntake`: decimal comma and point, whitespace and no-break-space thousands, "kcal" suffix, garbage refused.
- [x] 2.3 Tests: `ActiveCaloriesTests`, the store fixture in `StoreFixtureTests`.

## 3. The bridge (M)

- [x] 3.1 `GarminFood/Activity/RecordActiveCaloriesIntent.swift` ("Record Active Calories", `openAppWhenRun = false`): app-only, offered by the Shortcuts app as an action; a Garmin-connected install ignores it; every refusal has a spoken reason. Not added to the App Shortcuts list (Siri phrases are not needed for an automation).
- [x] 3.2 Settings > Activity (`ActiveCaloriesView`, standalone only): the last report time and the 3-step guide to build the shortcut and the automations. **Deviation:** no shared iCloud shortcut link (it can only be made on a phone); the guide names the actions instead.
- [x] 3.3 The 2-day notice on Today (`ActiveCaloriesTodayRow`).

## 4. Standalone surfaces (M)

- [x] 4.1 `DayLogLoader`: in standalone, the day's active kcal comes from `ActiveCaloriesStore` (and is re-read on every rebuild); Garmin installs unchanged. `GamificationEngine.activeKcalProvider` the same, so "goal met" uses the Target the ring shows.
- [x] 4.2 The existing "Active today" line and Target (`ActiveCalorieGoal`, from main) now work on standalone; the Activity screen names the source; add / edit / delete manual activities; manual entries greyed once Health reported the day.
- [x] 4.3 The partner theme's "Ohnivá vůle" counts days with at least 300 active kcal (`PartnerAchievements.activeDayKcal`).

## 5. Verify (S)

- [ ] 5.1 CI green.
- [ ] 5.2 Her phone: a day of real Active Energy arrives through the automation and matches the Health app; a manual entry is not double counted; the notice appears after 2 days with the automation off. **Waits for the phone test.**
