# Exercise catalog (workout screen)

The workout screen (`StrengthWorkoutView`, openspec `add-workout-tracker`)
lists the exercises the **plan** names and shows a picture and cues for the
ones this catalog knows. The plan is written in the Obsidian vault (the
`plan-week` skill); the phone only reads it.

## For whoever writes a plan (an AI session too)

- An exercise step in a workout is `kind: exercise` with `name`, `sets`,
  `reps`, `load`, `tempo`, `side`, `note`.
- Use a name the catalog already knows when one fits: the `name.en`/`name.cs`
  or any `aliases` entry of an exercise in
  `ios/FoodLogCore/Sources/FoodLogCore/Resources/exercise-catalog.json`
  (Czech or English, case and diacritics do not matter; "Paused bench press"
  still finds the bench press). 31 main lifts are in it.
- An exercise the catalog does not know still works: it is listed and the
  weights are logged; it just has no pictures (and "Watch how" searches the
  web). **To give it pictures, add it to the catalog -- one command below.**

## Add an exercise (about a minute, no Swift)

```sh
# 1. find it in the public-domain database
node tools/exercise-catalog/add-exercise.mjs search "bulgarian split"

# 2. add it (downloads two pictures + writes the catalog entry)
node tools/exercise-catalog/add-exercise.mjs add Split_Squats \
  --slug split-squat --en "Split squat" --cs "Dřep s nohou vzadu" \
  --aliases "split squat,bulgarian split squat,dřep s nohou vzadu" \
  --cues-en "Front shin near vertical.|Drop straight down.|Weight over the front foot." \
  --cues-cs "Přední holeň svisle.|Klesej přímo dolů.|Váha nad přední nohou."

# 3. check and ship it
#    - the FoodLogCore tests (WorkoutTrackerTests) check ids, cues and pictures
#    - commit the new jpgs in ios/GarminFood/Resources/Exercises and the JSON
```

Notes:

- Pictures come from [free-exercise-db](https://github.com/yuhonas/free-exercise-db)
  (**Unlicense, public domain**), so they may live in this public repository.
  Do not add pictures from anywhere else without checking the licence.
- Always give `--aliases` for the names the plan may use (both languages).
  The longest alias found as whole words in the plan's name wins, so add the
  specific alias ("romanian deadlift") rather than relying on a generic one.
- Without `--cues-en` the database's first three English steps are used and
  the Czech cues repeat them; give both for a proper Czech screen.
- A curated video: `--video <url>` (otherwise "Watch how" opens a search).
- The database has no video; do not bundle videos (size, licence).
