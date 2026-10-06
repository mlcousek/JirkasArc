## ADDED Requirements

### Requirement: A weigh-in can be logged without the weigh-in screen

The system SHALL let a weigh-in in kilograms be logged from an App
Shortcut. It SHALL be saved on the phone before anything is sent and, in
Garmin mode, queued in the durable weight outbox for
`POST /weight-service/user-weight` (live-verified 2026-09-23); in
standalone mode it is saved on the phone only. A weight that is not above
0 and below 500 kg SHALL be refused with nothing saved. When the app is
running, its weight card and sync queue count SHALL show the new weigh-in.

#### Scenario: Saved offline

- **WHEN** the shortcut logs 75.5 kg in airplane mode
- **THEN** the weigh-in is in the weight history as not yet synced and one entry waits in the weight outbox

#### Scenario: Not a weight

- **WHEN** the shortcut is given 0 or 500
- **THEN** nothing is saved or queued and the answer asks for a weight between 0 and 500 kg

#### Scenario: Standalone

- **WHEN** the shortcut logs 60 kg on a standalone install
- **THEN** the weigh-in is saved on the phone, nothing is queued and the answer does not mention Garmin
