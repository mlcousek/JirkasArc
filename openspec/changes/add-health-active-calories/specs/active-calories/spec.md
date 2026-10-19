## ADDED Requirements

### Requirement: Active calories are stored per day, and a Health report wins over manual entries

The system SHALL store, per calendar day, the latest Active Energy total
reported from Health and any manually entered activities, and SHALL
include them in backups. A newer Health report for a day SHALL replace the
older one. The day's total SHALL be the Health value when one exists,
otherwise the sum of the manual activities. No screen or save SHALL wait
for a report.

#### Scenario: Shortcut runs twice

- **WHEN** reports of 310 kcal at 14:00 and 455 kcal at 18:00 arrive for the same day
- **THEN** the day's total is 455 kcal

#### Scenario: No double counting

- **WHEN** she entered a manual run of 300 kcal and Health then reports 640 kcal for that day
- **THEN** the day's total is 640 kcal, and the manual run is still listed, marked as already counted by Health

#### Scenario: Manual only

- **WHEN** a day has no Health report and manual activities of 200 and 150 kcal
- **THEN** the day's total is 350 kcal

#### Scenario: Out of range

- **WHEN** a report arrives dated tomorrow, or 8 days ago, or with 12 000 kcal
- **THEN** it is refused and stored activity is unchanged

### Requirement: The Shortcuts bridge records active calories without opening the app

The system SHALL provide an App Intent that accepts a date (default today)
and an active-calorie total written with a decimal comma or point, and that
records it by the rules above without opening the app. Settings SHALL show
the time of the last report and the setup guide. When the bridge has
reported before and nothing has arrived for 2 days, Today SHALL show a
quiet notice linking to the guide.

#### Scenario: Czech decimal comma

- **WHEN** the intent receives "412,5" for today
- **THEN** today's Health value is 412.5 kcal and the app was not opened

#### Scenario: Bridge silent

- **WHEN** the last report is 2 days old
- **THEN** Today shows "Zdraví se 2 dny neozvalo" with a link to the guide

### Requirement: Activities can be entered by hand

On a standalone install the system SHALL let the user add, edit and delete
an activity with a type, optional minutes and 1–3 000 kcal for a day.

#### Scenario: Adding a walk

- **WHEN** the user adds "Chůze, 45 min, 180 kcal" for today with no Health report
- **THEN** today's active total is 180 kcal and the walk is listed on Today

### Requirement: Standalone shows active calories like a Garmin install, and Garmin installs are unchanged

On a standalone install with a total for the day, the system SHALL show the
"Active today" line with that total and its source, and SHALL apply the
active-calorie goal from it. Without a total, standalone SHALL be
unchanged. A Garmin-connected install SHALL keep Garmin as its only source
and SHALL ignore bridge reports.

#### Scenario: Standalone with a report

- **WHEN** a standalone install has a Health report of 420 kcal for today
- **THEN** the summary card reads "Aktivní dnes: 420 kcal (ze Zdraví)" in Czech and no Garmin request is sent

#### Scenario: Garmin install

- **WHEN** a Garmin-connected install receives a bridge report
- **THEN** the report is ignored and the "Active today" line still shows Garmin's value
