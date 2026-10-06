## ADDED Requirements

### Requirement: A drink can be logged without the water screen

The system SHALL let a drink in millilitres be logged from an App Shortcut
and from a Control, one 250 ml glass when no amount is given. It SHALL be
saved on the phone before anything is sent and, in Garmin mode, queued in
the durable hydration outbox for
`POST /usersummary-service/usersummary/hydration/log` (device logs observed
arriving in Garmin on 2026-09-23); in standalone mode it is saved on the
phone only. An amount that is not above 0 and below 5000 ml SHALL be
refused with nothing saved. When the app is running, its water card SHALL
count the new drink.

#### Scenario: The default glass

- **WHEN** the water shortcut runs with no amount
- **THEN** a 250 ml drink is saved for now and the shown total rises by 250 ml

#### Scenario: A chosen amount

- **WHEN** a shortcut runs "Log water" with 500 ml
- **THEN** a 500 ml drink is saved

#### Scenario: Not an amount

- **WHEN** the shortcut is given 0 ml or 5000 ml
- **THEN** nothing is saved or queued
