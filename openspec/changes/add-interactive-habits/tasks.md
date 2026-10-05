# Tasks: add-interactive-habits

## 1. TrainingCore

- [x] 1.1 Decode `habits.ladder[].streak`, `history` and `adherence` tolerantly (`Contract/HabitTracking.swift`, `Projection.swift`).
- [x] 1.2 `Plan/HabitTimeline.swift`: the day states (done, partly, missed, not expected, unknown), the streak rule (a silent past expected day is a miss; today never breaks the streak before it is over; a day nothing was expected on neither counts nor breaks) and the local fallback when the vault fields are absent.
- [x] 1.3 `ViewModels/HabitModels.swift`: the Habits screen, the habit detail (today control, multi-dose counter, current and best streak, adherence 7 / 14 / 30 / 84 days, 12-week calendar, recent entries, back-fill window) and the Today card rows.
- [x] 1.4 The phone's pending ticks lie over the vault's numbers; a refused tick is kept with its reason and is not laid over the plan (`Events/CheckInOverlay.swift`).
- [x] 1.5 Strings in English and Czech (`TrainingKey`, both `.lproj` tables, plural forms in `.stringsdict`).
- [x] 1.6 Tests: `HabitTimelineTests`, `HabitModelTests` (synthetic fixtures in `Support/HabitFixtures.swift`).

## 2. App

- [x] 2.1 `Habits/HabitsScreen.swift`: the ladder as steps (done, active, locked with the unlock condition).
- [x] 2.2 `Habits/HabitDetailView.swift`: today control, streaks, adherence, calendar, entries, back-fill within the vault's window, un-tick, the refused tick's reason.
- [x] 2.3 `Habits/HabitsTodayCard.swift`: one tap per expected habit with its streak; a long press opens the detail; a small moment when the day's habits are all done.
- [x] 2.4 Ticks go through the existing check-in recorder (`habit.tick`); nothing is sent unless the vault connection is configured.
- [x] 2.5 `Shortcuts/TickHabitIntent.swift`: "Tick habit" for Shortcuts and Siri.
- [x] 2.6 Merged with `main` (daily check-in on skeleton days, pain mode, training gamification, badge art).

## 3. Checks

- [x] 3.1 `openspec validate add-interactive-habits --strict`, `node tools/check-localizations.mjs --scan`, `sh tools/lint-design-tokens.sh`.
- [ ] 3.2 CI green (the first compile of this Swift).
- [ ] 3.3 On the phone: tick and un-tick today, back-fill a past day, check the streak after a silent day, open the detail from Today and from Plan, run the "Tick habit" shortcut.
