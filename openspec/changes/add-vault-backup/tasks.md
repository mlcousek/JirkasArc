Every task ends with CI green: `swift test` for FoodLogCore and VaultKit,
the design-token lint, the app and widget `xcodebuild`, and the
`localization` job. Every new `.swift` file starts with a header comment
saying why it exists and what depends on it. All new user-facing text is in
English and Czech. **Nothing personal in the repository**: test data is
synthetic (`example-owner/example-vault`, device `ios-0000abcd`, dates in
2030, planted tokens assembled at run time), and no token, account id, real
weight, health history or the name of the notes repository is written into
code, tests, fixtures or docs. `HubEvent.swift`, the mirrored contract
fixtures and their golden tests are not touched. No new dependency, target,
entitlement or background mode. Branch `mlcousek/vault-backup` on `main`.
Relative size: S / M / L.

A box is ticked when the code was written and read back against its call
sites and tests; nothing here was compiled locally (no Swift toolchain),
so sections 6.3 and 7 stay open until CI and the phone have said so.

## 1. Design (S)

- [x] 1.1 Read `add-data-safety`, `add-vault-connection` and `add-training-checkins` as built; estimate the archive's size from the store fixtures; check the gzip framing and the ISO-week arithmetic with Node.
- [x] 1.2 `proposal.md`, `design.md` (with "For the vault"), the three spec deltas and this file; `openspec validate add-vault-backup --strict`.

## 2. Pure rules in FoodLogCore (M)

- [x] 2.1 `Backup/BackupArchive.swift`: gzip (RFC 1952 header and trailer around Foundation's raw DEFLATE), gunzip (the optional header fields skipped, CRC-32 and length checked, a declared size above 256 MB refused), `CRC32`, `BackupUploadArchive` and `BackupVault.makeUploadArchive` (the export container, compressed; `nil` for an empty data set).
- [x] 2.2 `BackupContainer.decode` unpacks a gzip file first; a damaged one is `notABackup`.
- [x] 2.3 `BackupReminderPolicy`: `lastVaultBackupAtKey` and `shouldShow(..., lastVaultBackupAt:)`.
- [x] 2.4 `StoreCatalog`: `vault.backup-upload` (device only, not in backups).
- [x] 2.5 Tests: `BackupArchiveTests` (the CRC-32 check value, the round trip, two real gzip files, damaged and oversized input, a gzip file through `BackupContainer.decode`), `VaultUploadArchiveTests` (the upload equals the export; planted secrets and device state never in it; the named never-uploaded stores; an empty data set), the reminder's new cases, the catalog test's new file.

## 3. Pure rules in VaultKit (M)

- [x] 3.1 `VaultPathPolicy`: writes to `backups/<ownDeviceId>/<yyyy>/<name>.json.gz`, nothing else under `backups/`, no reads.
- [x] 3.2 `VaultBackup.swift`: `VaultBackupWeek` (ISO week in UTC), `VaultBackupPath` (the weekly and the time-stamped name, the commit message), `VaultBackupFailure` (what counts as an attempt), `VaultBackupState` (success and failure bookkeeping), `VaultBackupSchedule` (due or not, the interval, the weekly bound, the cap).
- [x] 3.3 `VaultBackupUploader.swift`: `VaultBackupStateStore` (`backup-upload.json`) and `VaultBackupUploader` (the cap, create-only, "already exists" is done, the time-stamped name for a manual backup, the connection status fed with a success or a rate limit only).
- [x] 3.4 Store fixture `backup-upload.json` and its test; `allFixtures`.
- [x] 3.5 Tests: `VaultBackupTests` (weeks at year boundaries, paths, the policy's allowed and refused shapes, due and not due, counted and uncounted failures, the week rollover) and `VaultBackupUploaderTests` over the in-memory transport and the GitHub client behind the URL stub (created, already there, the lost answer, too large, offline, server error five times, manual in a done week, another device's folder).

## 4. The app (M)

- [x] 4.1 `VaultServices`: the state store and the uploader, one per process.
- [x] 4.2 `Vault/VaultBackupService.swift`: the gate (connection on, device id, request gate), `runIfDue`, `backUpNow`, the archive built on `DataSafetyQueue`, the reminder's date, the auth hook, Diagnostics lines.
- [x] 4.3 `AppEnvironment` (after the event delivery, on foreground) and `BackgroundRefresh.run`.
- [x] 4.4 `VaultSettingsView`: the "Backup" section and "Backups folder" under Details; `VaultErrorPresentation`: the failure and result texts.
- [x] 4.5 `DataSettingsView`: the importer accepts `.gz`; `BackupReminderBanner`: the vault backup's date.

## 5. Strings (S)

- [x] 5.1 App `Localizable.xcstrings`: every new key with Czech (text insertion on the raw bytes, CRLF, no JSON round-trip).

## 6. Checks (S)

- [ ] 6.1 `openspec validate add-vault-backup --strict`, `node tools/check-localizations.mjs --scan`, `sh tools/lint-design-tokens.sh`, the TrainingCore key check.
- [ ] 6.2 Docs: `docs/vault-connection.md` (the write table, Backups), `CLAUDE.md` (VaultKit, FoodLogCore, what is written to the vault); this design kept as built.
- [ ] 6.3 **Requires CI.** `swift test` for FoodLogCore and VaultKit, the app and widget `xcodebuild`, the localization export comparison. `testRealGzipFilesDecode` is the proof that Foundation's `.zlib` is a raw DEFLATE stream.

## 7. On the phone (not verifiable here)

- [ ] 7.1 First foreground after the update with a working connection: one commit `hub: <device> backup <YYYY>-W<ww>.json.gz (...)` in the vault; a second foreground the same week sends nothing.
- [ ] 7.2 Settings > Vault > Backup shows the date and the size. Write the real size into design.md D6 beside the estimate.
- [ ] 7.3 "Back up now" in the same week creates the time-stamped file and shows "Backed up to the vault".
- [ ] 7.4 Restore: take the file from the vault into Files, Settings > Data > Import backup, the preview shows plausible counts; confirm on a spare install or cancel.
- [ ] 7.5 Unpack one file on the desk (`gunzip` or 7-Zip): it is the readable export JSON and contains no token.
- [ ] 7.6 Airplane mode at foreground on a Monday: no banner, "Last problem" says offline, the backup arrives within the hour after the network is back.
- [ ] 7.7 The vault's own tooling (pull, ingest) is not disturbed by the new `backups/` folder.
