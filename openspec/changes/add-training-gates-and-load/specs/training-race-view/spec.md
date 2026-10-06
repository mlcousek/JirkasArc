## ADDED Requirements

### Requirement: The Race screen shows how the race ended

When the vault publishes a result for a race, the Race screen SHALL show
it in neutral words -- "Finished", "Did not finish" or "Did not start",
with the reason for the last two -- together with the recorded distance,
the laps of a lap race, where the record came from (the race report or the
app) and its note. "Goal reached" and "Personal record" SHALL be shown
only when the vault says `true`; `false` and "not known" SHALL show
nothing. The app SHALL NOT infer a goal, a record or a status.

#### Scenario: A finished marathon

- **WHEN** the vault publishes a finish in 3:24:10 over 42.2 km with the goal reached, from the app's own result
- **THEN** the screen shows "Finished", "3:24:10", "42.2 km", "Goal reached" and "Logged in the app"

#### Scenario: Stopped by the rule

- **WHEN** the vault publishes a race not finished with the reason `stop-rule` after 6 laps
- **THEN** the screen shows "Did not finish", "Stopped by the stop rule" and "6 laps"

#### Scenario: Not known is not shown

- **WHEN** a result has `pr: null` and `goalReached: false`
- **THEN** neither "Personal record" nor "Goal reached" is shown

### Requirement: The organiser's time is the result and the elapsed time the second line

When a result carries an `officialTime`, the Race screen SHALL show it as
the race's time and the elapsed `time` as a second line marked as elapsed.
When it carries none, the elapsed `time` SHALL be the race's time and
there SHALL be no second line. Neither time SHALL be copied into the
other.

#### Scenario: Two times

- **WHEN** a result has `time` 0:46:03 and `officialTime` 0:45:41
- **THEN** the screen shows 0:45:41 as the result and "0:46:03 elapsed" under it

#### Scenario: One time

- **WHEN** a result has `time` 3:24:10 and no `officialTime`
- **THEN** the screen shows 3:24:10 alone

### Requirement: A race result can be recorded from the Race screen

When the vault connection can record and the race report does not state
the result, the Race screen SHALL offer a result sheet: on or after race
day with the statuses finished, did not finish and did not start; before
race day with "did not start" only, and only in the 14 days before the
race. The sheet SHALL ask for a reason when the race was not finished or
not started (including "Stopped by the stop rule"), the elapsed time and
an optional results time as `h:mm:ss`, the distance, the laps of a lap
race and an optional note, and Save SHALL record a `race.result` event.
Save SHALL be disabled while a time is not `h:mm:ss` or a number is not a
number. Until the vault has read it, the screen SHALL show this phone's
result with its delivery state and without a goal or record mark. The
owner SHALL be able to withdraw this phone's result, which retracts every
standing `race.result` of this phone for that race.

#### Scenario: Race day

- **WHEN** the owner opens the sheet on race day and saves "Did not finish", "Stopped by the stop rule", 2:10:00 and 19 km
- **THEN** a `race.result` event with that status, reason, time and distance is recorded and the screen shows it as saved on the phone

#### Scenario: Before race day

- **WHEN** the race is eleven days ahead
- **THEN** the sheet offers "Did not start" only and says why

#### Scenario: Far ahead

- **WHEN** the race is more than 14 days ahead and has no result
- **THEN** no result card is shown

#### Scenario: The report states the result

- **WHEN** the result's source is the race report
- **THEN** no sheet is offered

### Requirement: A refused result shows the vault's reason

When the projection's outcomes name this phone's `race.result` as refused,
the Race screen SHALL show the vault's reason in the app's language (a
generic sentence when the vault gave none) and SHALL NOT show the refused
result as the race's result.

#### Scenario: Sent before race day

- **WHEN** the vault refused a finish sent before race day and says why
- **THEN** the screen shows the vault's reason and no result
