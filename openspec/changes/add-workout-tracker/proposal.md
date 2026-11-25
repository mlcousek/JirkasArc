## Why

A gym session in the plan today shows its steps as one line of text each. At
the rack the owner wants to open the session, see each exercise as planned,
log the weight and reps of every set, see what they lifted last time, and see
how the movement looks. He wants this for his everyday training now, with the
exercise library easy to extend and the AI-written plan feeding it.

## What Changes

- **A workout screen** ("Start workout" on a gym session's detail): one card
  per planned exercise -- the plan's sets x reps, load, tempo and note; last
  time's sets; one row of weight and reps per set (saved on every keystroke);
  and "How to do it" (two frames, three cues, a way to watch it).
- **The plan is the source.** Exercises are the `exercise` steps of the
  vault's workout library (`Step.name/sets/reps/load/tempo/side/note`, already
  in the projection contract). When the AI writes a plan with different
  exercises, they appear here with no app change. The phone never writes the
  plan and never computes what the vault computes.
- **An exercise catalog** (`exercise-catalog.json`): 31 main lifts (bench
  press, squat, deadlift, overhead press, rows, pull-ups, ...) with English and
  Czech names, aliases the plan may use, three cues each and two frames. A name
  is matched ignoring case and diacritics, by exact alias first, else the longest
  alias inside the name. Adding an exercise is one JSON object plus up to two
  images, no code. An exercise the catalog does not know is still listed and
  loggable (and offers a video search).
- **A local gym diary** (`workout-log.json`, `WorkoutLogStore`): sets keyed by
  session and exercise, replace-on-edit, "last time" from the latest other
  session. Backed up with the owner's other local stores.
- **Pictures** come from the public-domain free-exercise-db (Unlicense),
  bundled in the app (no network at the rack). A curated video link per
  exercise is a `video` field; without one, "Watch how" searches the form.

## Impact

- TrainingCore: `ViewModels/StrengthWorkoutModel.swift` (+ tests on the
  vault's example fixture; no contract change, `HubEvent` untouched).
- FoodLogCore: `Workout/ExerciseCatalog.swift`, `Workout/WorkoutLog.swift`,
  the bundled catalog, `StoreCatalog` entry, store fixture and tests.
- App: `Workout/StrengthWorkoutView.swift`, "Start workout" in
  `SessionDetailView`, the store in `AppServices`/`AppEnvironment`, 62 images
  under `Resources/Exercises` (3.8 MB), strings.
- No Garmin route, no vault write, no network at run time.

## Non-goals (later)

Rest timers, a plan editor, personal records and charts, writing the
weights to the vault or Garmin (needs a new event kind in the vault's
contract), an exercise picker for sessions the plan does not describe.
