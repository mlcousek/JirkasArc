## ADDED Requirements

### Requirement: A gym session opens a workout screen

A session whose workout has `exercise` steps SHALL show "Start workout" in its
detail, opening one card per exercise in plan order with its sets x reps, load,
tempo, side and note as the plan wrote them. A session without exercise steps
SHALL NOT show the button.

#### Scenario: The plan changes

- **WHEN** the plan is rewritten with different exercises
- **THEN** the workout screen lists the new exercises without an app update

### Requirement: Log weight and reps per set

Each planned set SHALL have a weight and a reps field. A change SHALL be saved
on the phone at once, and re-entering the same set SHALL replace it. Clearing
both fields SHALL remove the set. A decimal comma SHALL be accepted.

#### Scenario: Leaving mid-workout

- **WHEN** the owner types a weight and closes the app
- **THEN** reopening the workout shows that weight

### Requirement: Last time

An exercise SHALL show the sets lifted in its most recent other session, and
use them as the fields' placeholders.

#### Scenario: First time

- **WHEN** the exercise was never logged
- **THEN** no "Last time" line is shown

### Requirement: How to do it

An exercise the catalog knows (by name or alias, ignoring case and diacritics)
SHALL offer its two frames, its cues in the app's language, and a way to watch
it. An exercise the catalog does not know SHALL still be listed and loggable and
SHALL offer a video search.

#### Scenario: Czech plan name

- **WHEN** the plan names "Tlak na lavici"
- **THEN** the bench press pictures and Czech cues are shown

### Requirement: The diary stays local

The weights SHALL be stored only in the app's `workout-log.json`, included in
the owner's backup; they SHALL NOT be sent to Garmin or the vault.
