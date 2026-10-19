## ADDED Requirements

### Requirement: A pack-unlocked theme beside the built-in themes

The system SHALL list the partner theme in the theme picker, after the 13
built-in themes, only while a valid love pack is stored. It SHALL NOT
encode the partner theme into a share code, and SHALL refuse to apply a
share code that names it. When the stored theme is the partner theme and
no valid pack is stored, the system SHALL render GF Teal.

#### Scenario: Share code

- **WHEN** the user taps "Share look" while the partner theme is active
- **THEN** the app says this theme can't be shared and no code is produced

#### Scenario: Pack missing at launch

- **WHEN** the app launches with the partner theme stored as active and no pack file present
- **THEN** every screen renders GF Teal and the partner theme is not in the picker
