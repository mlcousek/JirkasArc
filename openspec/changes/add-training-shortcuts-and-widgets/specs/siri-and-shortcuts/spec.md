## MODIFIED Requirements

### Requirement: The app exposes a small, fixed set of App Shortcuts

The system SHALL declare no more than 10 App Shortcuts, Apple's
compile-time limit (it was 5 before the training experience added actions
worth saying), and each phrase SHALL include the application-name token so
it is voice-triggerable via Siri and discoverable in Spotlight. Every
phrase SHALL have a Czech form.

#### Scenario: Invoking a shortcut by voice

- **WHEN** the user speaks a declared shortcut phrase including the app's name
- **THEN** the corresponding action is performed, without opening the app first where the action supports running in the background

#### Scenario: Shortcut count stays within platform limits

- **WHEN** a new shortcut is proposed for addition
- **THEN** it is only added if the total remains at or below 10

## ADDED Requirements

### Requirement: The morning check-in is an App Shortcut

The system SHALL offer the morning check-in as an App Shortcut with the
phrases "Morning check-in in <app>" and "<Green | Amber | Red> in <app>".
The light SHALL be the shortcut's parameter; when none is given the system
SHALL ask for it before anything is recorded. The shortcut SHALL answer
with a confirmation naming the recorded light.

#### Scenario: Saying the light

- **WHEN** the owner says "Amber in Jirka's Arc" on an install with a tested vault connection
- **THEN** an amber check-in is recorded for the current training day and the confirmation says "Amber"

#### Scenario: No light said

- **WHEN** the owner says "Morning check-in in Jirka's Arc"
- **THEN** the system asks "Green, amber or red?" and records nothing until one is chosen

#### Scenario: Connection off

- **WHEN** the shortcut runs on an install whose vault connection is off
- **THEN** nothing is recorded and the answer says to turn the vault connection on first

### Requirement: Weight and water are App Shortcuts

The system SHALL offer "Log weight in <app>" and "Log water in <app>" as
App Shortcuts. The weight shortcut SHALL ask for the weight in kilograms
when it is not given. The water shortcut SHALL log one 250 ml glass when no
amount is given. Each SHALL answer with what happened: saved, synced to
Garmin, or saved but unable to reach Garmin until the user signs in again.

#### Scenario: Weight by voice

- **WHEN** the user says "Log weight in Jirka's Arc" and answers "75.5"
- **THEN** a 75.5 kg weigh-in is saved for now and the answer names "75.5 kg"

#### Scenario: Water by voice

- **WHEN** the user says "Log water in Jirka's Arc"
- **THEN** a 250 ml drink is saved for now

#### Scenario: Signed out of Garmin

- **WHEN** the weight shortcut runs in Garmin mode with an expired Garmin sign-in
- **THEN** the weigh-in is saved on the phone and the answer says it cannot reach Garmin until the user signs in again
