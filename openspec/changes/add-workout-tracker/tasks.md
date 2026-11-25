Same branch rules as `add-daily-motivation`; nothing was compiled locally (no
Swift toolchain). Paths are disjoint from that change, so commit them apart.
Relative size S/M/L.

## 1. TrainingCore (S)

- [x] 1.1 `StrengthWorkoutModel.swift`: `PlannedExercise`, `StrengthWorkoutModel`, `PlanBuilder.strengthWorkout`.
- [x] 1.2 `StrengthWorkoutTests` on the vault's example fixture (`gym-a`: calf raise, split squat; a run session has none).

## 2. FoodLogCore (M)

- [x] 2.1 `ExerciseCatalog.swift` + `exercise-catalog.json` (31 exercises, en + cs, cues, aliases).
- [x] 2.2 `WorkoutLog.swift`: `LoggedSet`, `WorkoutLogStore`, `SetEntryText`.
- [x] 2.3 `StoreCatalog` entry `foodlog.workout-log`, fixture `workout-log.json`, `StoreFixtureTests`, `WorkoutTrackerTests`.

## 3. App (M)

- [x] 3.1 `StrengthWorkoutView.swift`; "Start workout" in `SessionDetailView`; store in `AppServices` / `AppEnvironment`.
- [x] 3.2 62 frames in `Resources/Exercises` (free-exercise-db, Unlicense); 8 new strings (en keys + cs); `check-localizations` passes.

## 4. Verify

- [ ] 4.1 CI green: TrainingCore + FoodLogCore `swift test`, `xcodebuild`, `localization`.
- [ ] 4.2 On the phone, in a gym session: the images show (the jpgs reach the bundle root), a typed weight survives closing the app, "Last time" appears the second session.
- [ ] 4.3 Later: a curated `video` per exercise; a vault event for sets if the owner wants them in the vault.
