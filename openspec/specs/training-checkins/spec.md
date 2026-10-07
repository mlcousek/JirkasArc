# training-checkins Specification

## Purpose
Let the owner tell the plan how the day went: the morning check-in from Today or a Control, habit ticks, RPE and notes, shown at once before delivery and backed by training reminders.

## Requirements

### Requirement: Today offers the morning check-in

In the training experience, when the vault connection has a device id and
the plan has the selected training day, the training card SHALL offer a
morning check-in with three choices, G (green), A (amber) and R (red),
each distinguished by letter and shape as well as colour and read by
VoiceOver with its meaning. Choosing one SHALL record `checkin.morning` for
that training day with the day's traffic-light session, if any, and SHALL
mark the choice and the matching option card. The option cards SHALL keep
opening the session detail and SHALL NOT record anything.

#### Scenario: The 4:00 check

- **WHEN** at 04:05 the owner taps A on Today, and today has a G/A/R session
- **THEN** `checkin.morning {light: amber, sessionId: <that session>}` is recorded for the training day, the A button is selected and the A option card is marked as matching the morning check

#### Scenario: A rest day

- **WHEN** the day has no session
- **THEN** the check-in is still offered and recorded without a session id

#### Scenario: No device id

- **WHEN** the connection is on but "Test connection" never succeeded
- **THEN** no check-in row is shown and Today stays read-only

### Requirement: Lock-screen Controls record the morning check-in

The system SHALL offer three Controls, Green, Amber and Red, in the existing
widget extension. Each SHALL open the app and record the check-in there for
the current training day, using the cached plan only, and SHALL fail with a
visible message when the vault connection is off or has no device id.

#### Scenario: From the lock screen

- **WHEN** the owner taps the Amber Control at 04:02, before the day boundary has passed in the plan's time zone at 03:00
- **THEN** the app opens and an amber check-in is recorded for today's training day

#### Scenario: Connection off

- **WHEN** the Control is tapped on an install without the vault connection
- **THEN** nothing is recorded and the Control reports that the vault must be connected first

### Requirement: Habits are ticked on and off

When ticking is allowed, each habit row on Today SHALL have an on/off
toggle for the selected training day, past or future. Toggling SHALL record
`habit.tick {date, habitId, done}`. A row SHALL show the phone's latest
tick, otherwise on when the projection counts the habit as done that day.

#### Scenario: Evening holds

- **WHEN** the owner turns "holds" on for today
- **THEN** `habit.tick {habitId: "holds", done: true}` is recorded and the toggle shows on

#### Scenario: Logging tomorrow

- **WHEN** the day switcher shows tomorrow and the owner ticks a habit
- **THEN** the tick is recorded for tomorrow's date

### Requirement: A session can be rated and annotated

When rating is allowed, the session detail SHALL let the owner set an RPE
from 1 to 10 and save a note of at most 2000 characters, recording
`session.rpe` and `session.note` for that session and its date, and SHALL
show the latest values with their delivery state.

#### Scenario: After the long run

- **WHEN** the owner opens the long run's detail, taps 7 and saves "Calf tight after 25 km"
- **THEN** both events are recorded and the detail shows RPE 7 and the note, "Saved on phone"

### Requirement: Training reminders prompt the check-in and the habits

In the training experience, with training reminders on, the system SHALL
schedule a local "How do you feel today?" reminder at 04:05 on each of today
and tomorrow that has a session with options and no check-in yet, and an
"Evening habits" reminder at 20:10 on each of those days with expected
habits not all ticked. It SHALL remove them when the check-in or the ticks
are recorded, when the switch is off, and in the food-first experience.

#### Scenario: Already checked in

- **WHEN** the owner checks in at 03:50 via the Control
- **THEN** today's 04:05 reminder is removed

#### Scenario: Food-first install

- **WHEN** an install has no vault connection
- **THEN** no training reminder is ever scheduled

### Requirement: The food-first experience is unchanged

The system SHALL NOT show any check-in, tick or rating control, record any
event, or schedule any training reminder in the food-first experience or
on a standalone install.

#### Scenario: The fiancée's install

- **WHEN** a standalone install opens Today and Settings
- **THEN** it looks and behaves exactly as before this change

### Requirement: The morning check-in asks for the pain score

When the check-in row has a chosen light for the shown training day and
that day's pain is not recorded yet, the row SHALL offer a compact pain
step: one row per default site -- the Achilles sites scored on the most
recent earlier day that has an Achilles entry, else the left Achilles --
each pre-filled with 0, a 0-10 control in half steps per row, a way to
add another site (right or left Achilles, left or right knee, or other
with a short note of at most 200 characters) and to remove a row, and a
Save action. Saving SHALL record one `checkin.morning` for that day with
the same light, session and option as the row and `pains` from the rows
(`[]` when every row was removed). The step SHALL record nothing until
Save is tapped.

#### Scenario: One tap confirms zero

- **WHEN** the owner chose amber this morning, the pain is not recorded and nothing was scored before
- **THEN** the step shows "Achilles (left)" at 0/10, and tapping Save records `checkin.morning {light: amber, pains: [{site: achilles-left, score: 0}]}`

#### Scenario: Two sites

- **WHEN** the owner sets the left Achilles to 4.5 and adds the right knee at 1
- **THEN** Save records `pains` with both entries, and the card shows "Pain: Achilles (left) 4.5/10 · Knee (right) 1/10" (Czech "4,5/10")

#### Scenario: Default from the last scored morning

- **WHEN** the latest earlier day with pains scored both Achilles sites
- **THEN** the step opens with both Achilles rows at 0

### Requirement: The pain score can be corrected the same day

When the shown day's pain is recorded, the card SHALL show it and the row
SHALL offer to edit it; saving the edit SHALL record a new
`checkin.morning` with the same light and the new `pains`, which replaces
the earlier answer. Changing the light afterwards SHALL NOT erase the pain
answer.

#### Scenario: Edit after the run

- **WHEN** the morning check-in recorded the left Achilles at 2 and the owner edits it to 3
- **THEN** a check-in with `pains: [{site: achilles-left, score: 3}]` is recorded and the card shows 3/10

#### Scenario: Light corrected

- **WHEN** after recording the pain the owner changes the light from amber to green
- **THEN** the check-in is recorded without `pains` and the card still shows the recorded pain

### Requirement: The Controls stay light-only and the app offers the pain step

The lock-screen Controls SHALL keep recording the light only (no pain).
After a Control's check-in succeeds, the app SHALL show Today at the
current training day, where the pain step is offered because the day's
pain is not recorded yet.

#### Scenario: Amber from the lock screen

- **WHEN** the owner taps the Amber Control and the app opens
- **THEN** an amber check-in without pain is recorded and Today shows today's check-in row with the pain step open
