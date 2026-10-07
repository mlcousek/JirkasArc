## MODIFIED Requirements

### Requirement: All data can be exported to and imported from one file

The system SHALL export every included data file and preference as a single
`.json` backup file through the system file exporter (Files, iCloud Drive)
without any entitlement, SHALL record the export time, and SHALL import such a
file through the system file importer by checking its version, showing a
preview (backup date, app version, counts of food-log entries, custom foods,
meal presets, favourites, weigh-ins, drinks and day notes) and, on
confirmation, staging it as a restore. The importer SHALL accept the same
file gzip-compressed (`.json.gz`, as the weekly vault backup writes it),
with or without the optional gzip header fields, and SHALL refuse a
compressed file whose checksum or length does not match as "not a backup",
changing nothing.

#### Scenario: Move to a reinstalled app

- **WHEN** the user exports a backup to Files, deletes the app, reinstalls it, imports the file, confirms the preview and reopens the app
- **THEN** the food log, custom foods, meal presets, favourites, weight, water, day notes, preferences and progress are as they were at export, and Garmin asks for sign-in again

#### Scenario: Preview before anything changes

- **WHEN** the user picks a backup file with 12 custom foods and 40 weigh-ins
- **THEN** the preview shows 12 custom foods and 40 weigh-ins and no data has changed until she confirms

#### Scenario: A backup taken from the vault

- **WHEN** the user picks a `.json.gz` file that the weekly vault backup wrote
- **THEN** the preview shows that backup's date and counts, exactly as for the uncompressed export of the same data

#### Scenario: A damaged compressed file

- **WHEN** the user picks a `.json.gz` file whose last bytes were cut off
- **THEN** the app says it is not a backup and nothing is staged

### Requirement: The user is reminded to export

The system SHALL show in Settings → Data when the last export was made and,
when neither an export nor a backup that reached the vault was made in the
last 14 days, a quiet reminder in the Today banner area that can be
dismissed for 14 days, in both data modes. A recorded export, vault backup
or dismissal whose time lies in the future (the clock was set forward when
it was recorded) SHALL count for nothing.

#### Scenario: Reminder after two weeks

- **WHEN** the last export was 15 days ago, no backup reached the vault since, and the reminder was not dismissed
- **THEN** the Today screen shows the backup reminder until the user exports or taps "Not now"

#### Scenario: Dismissed

- **WHEN** the user taps "Not now" on the reminder
- **THEN** it does not appear again for 14 days

#### Scenario: The weekly vault backup works

- **WHEN** there has never been an export and a backup reached the vault 3 days ago
- **THEN** the reminder is not shown

#### Scenario: The weekly vault backup stopped

- **WHEN** there has never been an export and the last backup that reached the vault is 15 days old
- **THEN** the reminder is shown

#### Scenario: A backup dated in the future

- **WHEN** there has never been an export and the only recorded vault backup is dated one day after the current time
- **THEN** the reminder is shown
