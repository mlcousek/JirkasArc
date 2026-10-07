## ADDED Requirements

### Requirement: The app's data is backed up to the vault once per ISO week

While the vault connection is on, configured, tested (a device id exists)
and not blocked or rate limited, on a Garmin-connected install, the system
SHALL upload one backup of the app's data to the vault in every ISO week
(Monday to Sunday, UTC) in which the app runs, at the first opportunity:
when the app comes to the foreground, after the training events were
delivered, and during the existing background refresh. The upload SHALL
never be awaited by a screen or by a save. The system SHALL NOT upload
when any of those conditions does not hold, and SHALL NOT add a background
mode, an entitlement or a target for it.

#### Scenario: First foreground of a new week

- **WHEN** the app comes to the foreground on Monday with a working connection and no backup recorded for that ISO week
- **THEN** one backup file for that week is created in the vault and Settings > Vault shows its date and size

#### Scenario: Later the same week

- **WHEN** the app comes to the foreground again on Wednesday of the same ISO week
- **THEN** no backup request is sent

#### Scenario: Connection off

- **WHEN** the vault connection is switched off for a whole week
- **THEN** no backup request is sent that week and no error is shown

#### Scenario: Never tested

- **WHEN** the connection is configured but "Test connection" has never succeeded
- **THEN** no backup request is sent, because the phone has no device id to name its folder

### Requirement: The backup is the export file, compressed, at a fixed path in the phone's own folder

The uploaded file SHALL be the same backup container "Export backup"
writes, gzip-compressed, at the hub-relative path
`backups/<deviceId>/<YYYY>/<YYYY>-W<ww>.json.gz`, where `<deviceId>` is
this install's vault device id, `<YYYY>` the ISO week-numbering year and
`<ww>` the two-digit ISO week, both in UTC. The path SHALL be built from
the hub root the event upload uses, never from a repository path written
into the app. Unpacked, the file SHALL import through Settings > Data >
Import backup like any exported backup.

#### Scenario: A week in the middle of the year

- **WHEN** a backup is taken on 2030-10-14 at 08:15 UTC on the install `ios-0000abcd`
- **THEN** its path is `backups/ios-0000abcd/2030/2030-W42.json.gz`

#### Scenario: The week-numbering year differs from the calendar year

- **WHEN** a backup is taken on 2029-12-31 UTC, a Monday
- **THEN** its path is `backups/ios-0000abcd/2030/2030-W01.json.gz`

#### Scenario: Round trip

- **WHEN** the uploaded bytes are unpacked with a standard gzip tool and the result is imported
- **THEN** the import preview shows the same counts as an export taken at the same moment

### Requirement: A week's backup is created once and never overwritten

The system SHALL upload a backup with a create-only request. When the
answer is "a file already exists at this path", it SHALL read that path
once and, when a file is there, treat the week as backed up: a success,
with no further automatic request that week. When no file is there, or
the read fails, the week SHALL NOT be recorded as backed up and the
attempt SHALL be shown as failed. The system SHALL NOT overwrite or delete
a file in the backups folder, and SHALL NOT require the existing file to
equal the one it tried to upload.

#### Scenario: The answer was lost

- **WHEN** an upload reached the vault but its answer did not reach the phone, and the next attempt is answered "already exists"
- **THEN** the file is found there, the week is recorded as backed up, no second file is created and no error is shown

#### Scenario: A file is already there

- **WHEN** the vault already holds `2030-W42.json.gz` for this device, with other content, and the phone has no record of it
- **THEN** the existing file is left as it is and the week is recorded as backed up

#### Scenario: "Already exists" without a file

- **WHEN** a create is answered 422 and a read of the same path is answered 404
- **THEN** the week is not recorded as backed up, Settings > Vault shows the attempt as failed, and another attempt is made an hour later

### Requirement: A failed upload is retried later, within bounds

After a failed automatic attempt the system SHALL NOT try again sooner
than one hour later, and SHALL stop for the rest of the ISO week after
five failures that count. Being offline, a rejected token, a rate limit, a
connection that is not configured, an empty data set, a conflict with
another commit made at the same moment (409) and a request the system
cancelled SHALL NOT count, but SHALL still be held to the one-hour
interval. A week that ends without
a success SHALL be skipped: the next week starts with no failures counted.
A rate limit SHALL pause all vault requests until its reset time, as for
every vault request.

#### Scenario: Offline all day

- **WHEN** the app comes to the foreground ten times in one day without a network
- **THEN** at most one backup attempt per hour is made and none of them counts towards the week's five

#### Scenario: The event upload commits at the same moment

- **WHEN** six backup attempts in one week are each answered 409 because the phone's own event upload moved the branch
- **THEN** none of them counts, and a seventh attempt is made an hour after the sixth

#### Scenario: The background refresh is ended mid-upload

- **WHEN** iOS ends the background refresh while the backup is being uploaded
- **THEN** the attempt does not count towards the week's five and the next one is made an hour later at the earliest

#### Scenario: The server keeps failing

- **WHEN** five attempts in one week are answered with a server error
- **THEN** no sixth automatic attempt is made that week, Settings > Vault shows the last problem, and the next week a new attempt is made

#### Scenario: Works again

- **WHEN** an attempt fails with a server error and the attempt an hour later succeeds
- **THEN** the week is recorded as backed up and the last problem is no longer shown

### Requirement: A backup above the size cap is not uploaded

The system SHALL NOT upload a backup whose compressed size exceeds
3 MiB (3 145 728 bytes). It SHALL record the attempt as failed with the
size and the cap, and Settings > Vault SHALL say that the backup is too
large to upload.

#### Scenario: Too large

- **WHEN** the compressed backup is 3 145 729 bytes
- **THEN** no request is sent and Settings > Vault says the backup is too large, with both sizes

#### Scenario: At the cap

- **WHEN** the compressed backup is exactly 3 145 728 bytes
- **THEN** it is uploaded

### Requirement: The owner can back up by hand and sees the last backup

Settings > Vault SHALL show when the last backup reached the vault and
its size, the last problem with its time while the last attempt failed,
and a "Back up now" action. "Back up now" SHALL upload a backup at once
when the connection allows a request, regardless of the weekly schedule
and the retry bounds. In a week without a backup it SHALL create the
week's file. In a week that already has one it SHALL create a second file
`<YYYY>-W<ww>-<yyyymmdd>T<hhmmss>Z.json.gz` in the same folder, stamped in
UTC, so that every tap produces a current copy. When the connection does
not allow a request, the action SHALL say why and send nothing.

#### Scenario: First backup by hand

- **WHEN** the owner taps "Back up now" in a week without a backup
- **THEN** `<YYYY>-W<ww>.json.gz` is created and the automatic backup does not run again that week

#### Scenario: A second copy in the same week

- **WHEN** the owner taps "Back up now" on 2030-10-16 at 19:30:05 UTC in a week that already has a backup
- **THEN** `2030-W42-20301016T193005Z.json.gz` is created beside the weekly file, which is unchanged

#### Scenario: The connection was never tested

- **WHEN** the owner taps "Back up now" before any successful "Test connection"
- **THEN** nothing is sent and the screen says to test the connection first

### Requirement: The uploaded backup contains no credential and no device state

The uploaded backup SHALL contain exactly what an exported backup
contains. It SHALL NOT contain the Garmin tokens, the vault token, any
file or preference that looks like a credential by its name or its
content, the vault device identity, the vault status, the cached plan,
the write queue, the unsent training events, the outboxes, the
diagnostics log or the backup upload's own state.

#### Scenario: Planted secrets

- **WHEN** the data directory holds a file named like a token store, a store whose content carries an OAuth key, a store and a preference that each contain a GitHub token, every vault state file and an outbox
- **THEN** the unpacked upload contains none of those files, none of the planted values and not the device id

#### Scenario: A device-only store is flipped by mistake

- **WHEN** a developer changes the catalog entry of the vault device identity, the write queue or an outbox to be included in backups
- **THEN** a test fails and names the store

### Requirement: The backup needs nothing from the vault and changes no contract

The backup SHALL work without any code running on the vault's side. It
SHALL NOT change the training event envelope or the projection contract,
and the app SHALL read from the backups folder only to confirm that one
of its own files, reported as existing, is there.

#### Scenario: A vault that knows nothing about backups

- **WHEN** the vault's own tooling has never heard of the backups folder
- **THEN** backups are created every week and the events and the plan work as before
