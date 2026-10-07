## ADDED Requirements

### Requirement: A water Control logs one glass

The system SHALL offer a "Log Water" Control that opens the app and logs
one 250 ml drink there for the current time. Its label SHALL name the
action, not a live total. A failure SHALL be shown by the Control: an
expired Garmin sign-in is reported even though the drink is saved.

#### Scenario: One glass from Control Center

- **WHEN** the user activates the water Control
- **THEN** the app is briefly foregrounded and a 250 ml drink is saved for now

#### Scenario: Activated twice

- **WHEN** the user activates the water Control twice
- **THEN** two 250 ml drinks are saved

### Requirement: A weigh-in Control opens the weigh-in form

Because a Control cannot take a number, the system SHALL offer a "Log
Weight" Control that opens the app with the weigh-in form presented, and
SHALL NOT record a weigh-in until the user saves that form. When the app
cannot present the form at that moment, because first-run onboarding, the
shared-theme preview or an alert of the app is on screen, the request
SHALL be dropped: the form SHALL NOT appear by itself after that screen
closes.

#### Scenario: Opening the form

- **WHEN** the user activates the weight Control
- **THEN** the app opens with the weigh-in form on screen, whichever tab was showing

#### Scenario: During onboarding

- **WHEN** the user activates the weight Control on a fresh install that is still showing onboarding
- **THEN** the app opens on onboarding, and no weigh-in form appears when onboarding is finished

#### Scenario: Leaving without saving

- **WHEN** the user activates the weight Control and cancels the form
- **THEN** no weigh-in is saved or queued
