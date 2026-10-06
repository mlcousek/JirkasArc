## ADDED Requirements

### Requirement: The quick-log shelves follow the day being shown

The "Log again" and "Log a meal" shelves SHALL be shown on a past day and
on today whenever they have something in them, and a food or meal picked
from them SHALL be logged into the day being shown. On a day after today
they SHALL be shown only in the training experience, whose day switcher
can reach such a day. An empty shelf SHALL NOT be shown on any day.

#### Scenario: Catching up yesterday

- **WHEN** the day shown is yesterday and there are foods to log again
- **THEN** "Log again" is shown and a food picked from it opens the confirm screen dated yesterday

#### Scenario: Tomorrow in the training experience

- **WHEN** the training experience shows tomorrow and there are saved meals
- **THEN** "Log a meal" is shown

#### Scenario: A future day in food-first

- **WHEN** the food-first experience is asked about a day after today
- **THEN** neither shelf is shown

#### Scenario: Nothing to offer

- **WHEN** there are no foods to log again
- **THEN** "Log again" is not shown, whatever the day

### Requirement: A day's food log can be closed

Under the last meal card the app SHALL offer "That's everything today" on
today and on a past day that has at least one entry. Tapping it SHALL
record on the phone that the day's food log is complete, with the time. A
day without an entry and a day after today SHALL NOT be closable. A closed
day SHALL say that it is closed and SHALL offer an undo, which removes the
record. The record SHALL be kept on the phone only and SHALL survive a
relaunch. Both experiences SHALL offer it.

#### Scenario: Closing today

- **WHEN** today has three entries and the owner taps "That's everything today"
- **THEN** today is recorded as closed and the card says so

#### Scenario: Nothing logged

- **WHEN** the day has no entry
- **THEN** the day cannot be closed

#### Scenario: Undo

- **WHEN** the owner undoes a closed day
- **THEN** the day is no longer closed and can be closed again

#### Scenario: Relaunch

- **WHEN** a day was closed and the app is opened again
- **THEN** the day is still closed

### Requirement: A closed day that changes stays closed and says so

When an entry is added to, changed in or removed from a closed day through
the app, the day SHALL stay closed and SHALL say "Edited after closing".
Closing the day again after an undo SHALL clear that mark. A change to a
day that is not closed SHALL record nothing.

#### Scenario: Adding to a closed day

- **WHEN** a food is logged into a closed day
- **THEN** the day is still closed and says "Edited after closing"

#### Scenario: Closing it again

- **WHEN** an edited closed day is undone and closed again
- **THEN** the day is closed without "Edited after closing"

#### Scenario: An open day

- **WHEN** a food is logged into a day that is not closed
- **THEN** nothing is recorded about closing

### Requirement: Closed days in a row are counted beside the logging streak

The app SHALL show the number of closed days in a row: the run of closed
days ending today, or ending yesterday while today is not closed yet. A
day that is not closed SHALL end the run. A closed day that was edited
afterwards SHALL count. The existing streak of days with at least one
entry SHALL NOT change in any way.

#### Scenario: Today not closed yet

- **WHEN** the three days before today are closed and today is not
- **THEN** the count is 3

#### Scenario: A gap

- **WHEN** today and yesterday are closed, the day before is not, and the day before that is
- **THEN** the count is 2

#### Scenario: An edited day

- **WHEN** yesterday is closed and marked "Edited after closing" and today is closed
- **THEN** the count is 2

#### Scenario: Neither today nor yesterday

- **WHEN** the last closed day is two days ago
- **THEN** the count is 0

### Requirement: The evening reminder mentions an open food log

In the training experience the evening habits reminder of a day whose food
log is not closed SHALL also ask to close the food log. For a closed day
it SHALL read as it did before. The reminder SHALL still be planned only
for a day with expected habits that are not all ticked.

#### Scenario: Open habits, open food log

- **WHEN** today expects a habit that is not ticked and today's food log is not closed
- **THEN** the evening reminder says "Tick today's habits and close your food log."

#### Scenario: Food log already closed

- **WHEN** today expects a habit that is not ticked and today's food log is closed
- **THEN** the evening reminder says "Tick today's habits before bed."

#### Scenario: Nothing to tick

- **WHEN** every expected habit of the day is ticked
- **THEN** no evening reminder is planned for that day

### Requirement: Closing a day ticks the plan's food-log habit

In the training experience, when the plan's habit ladder has a habit with
the id `food-log` that takes ticks and the plan expects it on the day,
closing that day SHALL record a `habit.tick` for that date and habit with
`done: true`, and undoing the close SHALL record one with `done: false`,
through the recorder every other habit tick uses. Nothing SHALL be recorded
when the vault connection cannot record, when the ladder has no such habit,
when the plan does not expect it that day, when the day is outside the 14
days the vault accepts a tick for, or when the habit already is in that
state. The food-first experience SHALL record nothing.

#### Scenario: Expected today

- **WHEN** the ladder has `food-log`, the plan expects it today and today is closed
- **THEN** a tick for today, `food-log`, done, is recorded

#### Scenario: Undo

- **WHEN** that close is undone
- **THEN** a tick for today, `food-log`, not done, is recorded

#### Scenario: No such habit

- **WHEN** the ladder has no habit with the id `food-log`
- **THEN** closing the day records no tick

#### Scenario: Not expected that day

- **WHEN** the ladder has `food-log` and the plan does not expect it on the day being closed
- **THEN** closing the day records no tick

#### Scenario: The connection cannot record

- **WHEN** the vault connection is off or was never tested
- **THEN** closing the day records no tick and shows no error

#### Scenario: Too far back

- **WHEN** the day being closed is 20 days ago
- **THEN** the day is closed on the phone and no tick is recorded
