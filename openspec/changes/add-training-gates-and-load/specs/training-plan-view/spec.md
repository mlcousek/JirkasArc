## ADDED Requirements

### Requirement: The Plan week header shows the load against the plan

For a written week whose `actual` carries load fields, the week header
SHALL show the same load line as Today in place of the plain run line: the
week's run km of its target, km over plan when above 0, unplanned km, the
longest run of its cap, the climb and the hard sessions, a value the vault
does not know shown as "–". A week whose `actual` has none of the load
fields SHALL keep its plain run line.

#### Scenario: The current week

- **WHEN** the week has 10.1 of 55 km, nothing unplanned, a longest run of 10.1 km against a cap of 19.3 km, 60 m of climb and 0 hard sessions
- **THEN** the header reads "Week 10.1 of 55 km · 0 km unplanned · longest 10.1 of 19.3 km cap · hills 60 m · hard sessions 0"

#### Scenario: A week ahead

- **WHEN** the week has no `actual`
- **THEN** the header shows its run target as before

### Requirement: An unplanned run over the plan is marked, never praised

An unplanned activity the vault flags `over-plan` SHALL carry an "Over
plan" badge in the warning tint with a symbol. An activity without the
flag, or with a flag this build does not know, SHALL carry none. The app
SHALL NOT decide the flag itself.

#### Scenario: A flagged run

- **WHEN** an unplanned run of a day has `flag: "over-plan"`
- **THEN** its row carries the "Over plan" badge

#### Scenario: An unflagged ride

- **WHEN** an unplanned ride has `flag: null`
- **THEN** its row carries no badge

### Requirement: A session done by hand says so

A session whose `done.source` is `manual` SHALL read "Done (logged by
hand)" on Today's training card, in the Plan week's day rows and in the
session detail, and its detail SHALL show what was said (minutes,
distance, the note). When an activity matched and a manual
record exists as well, the session SHALL read as done by that activity,
with the manual record as one line.

#### Scenario: A gym session without a watch

- **WHEN** the vault publishes a gym session done with source manual and a record of 45 minutes with a note
- **THEN** the week row reads "Done (logged by hand)" and the detail shows the 45 minutes and the note under "Done without a watch"

#### Scenario: The activity won

- **WHEN** a session has a matched activity and a manual record of 55 minutes and 10 km
- **THEN** it reads "Done" with the activity, and "Also logged by hand: 55 min · 10 km"
