Every task ends with CI green (`swift test` for FoodLogCore, the app and
widget `xcodebuild`, `localization`). All new user-facing text is in
English and Czech. Nothing personal in the repository: test activity is
synthetic (dates in 2030). No entitlement, target or background mode.
Branch `mlcousek/health-active-calories` on `main`. Relative size: S / M /
L.

## 1. Probe (S)

- [ ] 1.1 Spike on her iPhone (iOS 26, Apple Watch paired): Find Health Samples (Active Energy, today) and Calculate Statistics (Sum) match the Health app's value; the number format under the Czech locale; a time-of-day automation with "Run immediately" runs unasked; an "app opened" automation runs. Record the iOS build, the date and the results in design.md "Probed".
- [ ] 1.2 For the record: does Strava's API answer for a Basic account (`GET /athlete` with a token from her own API app)? Record the status. Nothing is built on it.
- [ ] 1.3 `openspec validate add-health-active-calories --strict`.

## 2. Pure rules (S)

- [ ] 2.1 FoodLogCore `Activity/ActiveCaloriesDay.swift` (Health value replaced by newer, manual list, total rule, 7-day and future guards, 0–10 000 kcal), store `activity/days.json` (400 days, in backups).
- [ ] 2.2 `ActiveCaloriesIntake`: decimal comma and point, whitespace, units ("412,5 kcal") tolerated, garbage refused.
- [ ] 2.3 Tests for both.

## 3. The bridge (M)

- [ ] 3.1 `Shared/RecordActiveCaloriesIntent.swift` (`openAppWhenRun = false`), registered in `AppShortcuts`.
- [ ] 3.2 Build the shortcut, publish its iCloud link; Settings > Aktivita with the link, the 3-step guide, the last report time.
- [ ] 3.3 The 2-day notice on Today.

## 4. Standalone surfaces (M)

- [ ] 4.1 `DayLogLoader`: in standalone, `activeKilocalories` comes from `activity/days.json`; Garmin installs unchanged (test).
- [ ] 4.2 Summary card line with its source; the active-calorie goal; "Přidat aktivitu" sheet, list, edit and delete; greyed manual entries when Health reported.
- [ ] 4.3 Gamification signal "active-calorie goal met" for the partner theme.

## 5. Verify (S)

- [ ] 5.1 CI green on the PR.
- [ ] 5.2 Her phone: a day of real Active Energy arrives through the automation and matches the Health app within one run; a manual entry is not double counted; the notice appears after 2 days with the automation off.
