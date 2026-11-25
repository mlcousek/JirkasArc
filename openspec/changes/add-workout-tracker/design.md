## D1. Plan in, diary out

`PlanBuilder.strengthWorkout(sessionId:option:)` turns the chosen workout's
`exercise` steps into `PlannedExercise`s (TrainingCore, pure, read-only). The
chosen workout is the tapped option's, else the done option's, else G's, else
the first with exercises; a session without options uses its own. A step
without `sets` is one set; a step without a name is skipped; the id is
`<position>-<name>` so a repeated exercise stays distinct.

## D2. Why the log lives in FoodLogCore

`TrainingCore` has no `FoodLogCore` dependency and its stores are the vault's.
The owner's own diaries (weight, hydration, day notes, supplements) are
`FoodLogCore` JSON stores with the quarantining loader, a `StoreCatalog`
entry and a frozen fixture. `WorkoutLogStore` follows that, so it is backed up
and a corrupt file is quarantined instead of read as empty. The app target
joins the two packages (the plan's name -> the catalog's picture).

## D3. Matching a plan's name to the catalog

`ExerciseCatalog.normalize` lowercases, folds diacritics and reduces anything
but letters and digits to single spaces. `match` tries an exact key (id, both
names, aliases) first, then the longest key that appears in the name as whole
words, so "Romanian deadlift" is not "deadlift" and "Paused barbell bench press
(3 s)" is the bench press. A variant of a movement shows the nearest movement's
pictures (a front squat shows the squat): wrong in detail, never a wrong
exercise. The logged set's key is the catalog id, else the normalised name, so
history follows the exercise across spellings the catalog knows.

## D4. Saving

Each field change calls `WorkoutLogStore.record` (atomic file write, an actor).
A set is `(session, exercise key, set number)`: the same triple replaces, both
fields empty removes. Nothing waits on the network and a failed write is logged
to the Diagnostics log (the owner is standing at the rack trusting it). The
diary is not sent to the vault: its contract has no set event, and adding one is
a change to the vault repository first.

## D5. Pictures and videos

Images are the free-exercise-db's two frames per movement (Unlicense, public
domain; <https://github.com/yuhonas/free-exercise-db>), plain jpg files in the
app bundle root named by catalog `images` (`bench-press-0`). Video is not
bundled (size, licence): `video` holds a curated URL when the owner adds one,
otherwise "Watch how" opens a YouTube search for "<name> exercise form".

## D6. Adding exercises, and the AI

A new exercise = an object in `exercise-catalog.json` (id, en/cs name, aliases,
cues, image names, optional video) and its images in
`ios/GarminFood/Resources/Exercises`. The plan-writing skill only has to use a
name the catalog knows (or an alias); an unknown name still works. Every id and
alias is tested unique-id and well-formed by `WorkoutTrackerTests`.
