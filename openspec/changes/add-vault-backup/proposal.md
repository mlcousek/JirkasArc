## Why

Everything the owner logs lives in one place: the app's container on one
iPhone. The app already protects it there (`add-data-safety`): a snapshot a
day, kept on the phone, and "Export backup" into Files. Both stop short of
the case that matters most:

- **The snapshots are deleted with the app.** A lost phone, a wiped
  container or a build that will not launch takes them along.
- **The export needs a hand.** It is a button, and the reminder that asks
  for it comes every 14 days. Nobody exports weekly by hand for years.

The owner already has a place that is off the phone, versioned and his own:
the notes vault, which the app reaches through the vault connection
(`add-vault-connection`) and already writes its training events into
(`add-training-checkins`). A copy of the app's data there, once a week,
without being asked, closes the gap.

## What Changes

- **A weekly backup in the vault.** Once per ISO week the app uploads the
  same archive "Export backup" produces, gzip-compressed, to
  `backups/<this phone's device id>/<YYYY>/<YYYY>-W<ww>.json.gz` under the
  hub root, beside the events. Create-only: a file is never overwritten.
  When the week's file is already there, the week is done.
- **Only where the connection works.** The upload runs when the vault
  connection is on, tested and not blocked: the gate the event upload uses.
  On foreground (after the events are delivered) and inside the existing
  background refresh. No new background mode, entitlement or target.
- **Bounded retries.** A failed upload is tried again at most once an
  hour and at most five counted times a week. Being offline, a rejected
  token and a rate limit are not counted. A week without a success is
  skipped; the next week's file holds everything anyway.
- **"Back up now"** in Settings > Vault, with the last backup (date, size)
  and the last problem. In a week that already has a file it uploads a
  second, time-stamped file, so the button always produces a fresh copy.
- **A hard size cap.** An archive above 3 MiB is not uploaded and Settings
  says so.
- **Restore is the import the app already has.** "Import backup" also
  accepts the compressed file, so the owner picks the `.json.gz` straight
  from the vault.
- **The export reminder knows about it.** A vault backup in the last 14
  days counts as an off-phone copy; the "Keep a copy of your data" banner
  comes back when the weekly backup has not worked for two weeks.

## Capabilities

### New Capabilities

- `vault-backup` -- the weekly upload, its path and format, create-only,
  the retry bounds, the size cap, "Back up now" and what the archive may
  contain.

### Modified Capabilities

- `vault-transport` -- the write allow-list gains the phone's own backups
  folder; the upload's own state file joins the files a backup never
  contains.
- `data-safety` -- import accepts the compressed export; the export
  reminder counts a recent vault backup.

## Non-goals

- **Anything on the vault's side.** Nothing there has to run for the
  backup to work; the vault only has to tolerate a new folder. Listing the
  newest backup per device in its ingest report and pruning old files are
  the vault repository's own work (design.md "For the vault").
- **Restoring from inside the app.** The app does not list or download
  backups from the vault; the owner picks the file. A "Restore from the
  vault" screen is a later change if the manual step is ever in the way.
- **A second backup format.** No zip, no per-store upload, no deltas.
- **The event wire format.** `HubEvent.swift`, the mirrored contract
  fixtures and their golden tests are owned by `add-training-checkins` and
  are not touched.
- **Standalone installs.** They have no vault connection
  (`add-vault-connection`); their off-phone copy stays the export and its
  reminder (`add-data-safety`, `add-standalone-mode`).
- **Encrypting the archive.** The vault is the owner's private repository
  and already holds the same kind of data; the archive holds no credential.
- **The iCloud bridge.** `harden-vault-transport` may replace GitHub as the
  transport; the upload goes through `VaultTransport` and follows it.

## Impact

Grounded on `main` at `b628f91`; every name below was read in the code.

- VaultKit: `VaultPathPolicy` (the backups folder); new `VaultBackup.swift`
  (`VaultBackupWeek`, `VaultBackupPath`, `VaultBackupSchedule`,
  `VaultBackupState`, `VaultBackupFailure`), new
  `VaultBackupUploader.swift` (`VaultBackupStateStore`,
  `VaultBackupUploader`). A new device-local file
  `VaultKit/backup-upload.json` with a store fixture.
- FoodLogCore: new `Backup/BackupArchive.swift` (gzip framing over
  Foundation's DEFLATE, CRC-32, `BackupVault.makeUploadArchive`);
  `BackupContainer.decode` reads the compressed form;
  `BackupReminderPolicy` counts a vault backup; `StoreCatalog` gains
  `vault.backup-upload` (device only).
- App: new `Vault/VaultBackupService.swift`; `VaultServices`,
  `VaultSettingsView`, `VaultErrorPresentation`, `AppEnvironment`,
  `BackgroundRefresh`, `DataSettingsView` (the importer's file types),
  `BackupReminderBanner`. New EN + CS strings.
- Docs: `docs/vault-connection.md`, `CLAUDE.md`.
- No new dependency: compression is `NSData.compressed(using: .zlib)`.
- `HubEvent.swift`, the contract fixtures and the golden tests are not
  touched. TrainingCore is not touched.
- **Depends on**: `add-data-safety` (the export container, the staged
  restore, the exclusions), `add-vault-connection` (transport, path policy,
  device identity, status), `add-training-checkins` (the events folder the
  backups sit beside, the delivery hook on foreground).
- **Unblocks**: a vault-side report of the newest backup per device and a
  pruning rule; a later "Restore from the vault" screen.
