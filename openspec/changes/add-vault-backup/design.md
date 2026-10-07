## Context

Written 2026-10-07 on `mlcousek/vault-backup`, on `main` at `b628f91`.
This document is kept as built.

What the code already provided:

- **The backup machinery** (`add-data-safety`, FoodLogCore `Backup/`).
  `BackupVault.makeExportContainer` walks Application Support and puts
  every included file's exact bytes (base64) plus the typed preferences
  into one `BackupContainer`; `encoded()` is the pretty-printed JSON that
  "Export backup" saves as `JirkasArc-backup-<date>.json`. What is included
  is a deny list (`BackupExclusions`), so a store added later travels the
  day it ships. `BackupSecretPolicy` drops any file or preference whose
  content looks like a credential. Restore is two steps: `stageRestore`
  now, `applyPendingRestore` at the next launch before any store loads,
  after a safety snapshot. Import reads a picked file with
  `BackupContainer.decode`, shows a preview and stages it.
- **The vault connection** (`add-vault-connection`, VaultKit). Every
  request goes through `VaultTransport` with a hub-relative `HubPath`;
  `GitHubContentsClient` is the only type that builds a URL and prefixes
  `VaultHub.root`. `createFile` is a PUT without `sha`: GitHub creates the
  file or answers 422, never overwrites. `VaultPathPolicy` refuses every
  write outside `events/<ownDeviceId>/.../*.jsonl` before anything is sent.
  The device id (`ios-` + 8 hex) is created by the first successful "Test
  connection" and never leaves the phone's container.
- **The event upload** (`add-training-checkins`). `TrainingEventsService
  .drainNow` runs on foreground when the connection is on, configured, on a
  Garmin-connected install, with a token, no loud block and no rate-limit
  pause. Segments go through `DurableQueue` and `CreateOnlyFileUploader`,
  which on 422 reads the file back and compares git blob SHAs.
- **Gzip in FoodLogCore** (`add-offline-czech-food-index`,
  `OfflineFoodIndex.swift`). `GzipInflate` reads a gzip file (header with
  its optional fields, raw DEFLATE through `NSData.decompressed(using:
  .zlib)`, CRC-32 and length checked) and `GzipCRC32` computes the
  checksum. They decode the weekly-built Czech index, a real gzip file
  written by a Node tool, in production; that package's tests build their
  gzip files with `NSData.compressed(using: .zlib)` and the same ten-byte
  header. So that Foundation's `.zlib` is a raw DEFLATE stream is observed
  in this repository, not assumed.

What was probed: nothing new against GitHub. The create-only PUT, its 201
and its 422 are the ones the event upload has used since
`add-training-checkins`. Two things were checked on this machine with
Node, because no Swift runs here:

- the gzip framing the app writes (10-byte header, raw DEFLATE, CRC-32,
  length) is read back by a standard `gunzip`, and two real gzip files
  (one plain, one with a name, an extra field, a comment and a header
  checksum) are test vectors the reader must decode;
- the ISO-week arithmetic agrees with a reference implementation for every
  half day from 1999 to 2044.

No Swift toolchain here: correctness rests on the package tests and the
`xcodebuild` in CI, and on a phone for tasks.md section 7.

## Goals / Non-Goals

**Goals**

- A copy of the app's data outside the phone every week, without the owner
  doing anything.
- Restoring with the import the app already has.
- A bounded cost in the vault: one small file a week, a hard cap.
- No secret and no device state in the file, proven by tests.
- Every rule that can be wrong without a compiler lives in a package and is
  tested there.

**Non-goals**: see proposal.md.

## Decisions

### D1 -- The archive is the export, gzip-compressed

The uploaded bytes are `BackupContainer.encoded()` -- exactly what "Export
backup" writes -- passed through gzip. `BackupVault.makeUploadArchive`
builds both; the manifest's kind is `export`. No second format: one
decoder, one compatibility check, one preview, one restore.

The export is one file, so it can be uploaded as it is. It is not
compressed, and that is the one adaptation: it is pretty-printed JSON
holding base64, about 1.35 times the size of the stores it carries. Gzip
brings it to roughly a fifth (D6). The compression is Foundation's
(`NSData.compressed(using: .zlib)`, a raw DEFLATE stream) wrapped in the
gzip header and trailer by `BackupArchive.gzip`, with `GzipCRC32` for the
checksum. Gzip rather than a bare DEFLATE stream so that the file opens
with any tool on the desk (`gunzip`, 7-Zip, Node's `zlib.gunzipSync`) and
gives the plain export back.

`BackupContainer.decode` recognises the gzip magic bytes and unpacks first,
so every import path reads both forms. Unpacking is the offline index's
`GzipInflate`, not a second reader; it skips the optional header fields
(name, extra, comment, header checksum), which a file the owner unpacked
and packed again on the desk carries. `BackupArchive.gunzip` adds two
things a backup needs: a declared size above 256 MB is refused before
anything is unpacked, and every failure -- a wrong checksum, a wrong
length, a cut-off file -- is "not a backup", like any other unreadable
file. The file importer accepts `.gz` beside `.json`.

*Alternative considered:* gzip the raw store files instead of the base64
container (about a quarter smaller again). Refused: it is a second format
with its own reader, for a saving the cap does not need.

*Alternative considered:* upload the uncompressed `.json`. Refused: three
to five times the bytes in the vault's working copy on the phone, every
week.

### D2 -- One file per ISO week in the phone's own backups folder

```
<hub root>/backups/<deviceId>/<YYYY>/<YYYY>-W<ww>.json.gz
```

- `<hub root>` is `VaultHub.root`, prefixed by `GitHubContentsClient` as
  for every request. The app builds only the hub-relative `HubPath`
  (`VaultBackupPath.weekly`), never a repository path.
- `<deviceId>` is this install's vault device id, the one that names its
  events folder.
- `<YYYY>` is the ISO week-numbering year and `<ww>` the ISO week (01 to
  53), both in **UTC** (`VaultBackupWeek`). 2029-12-31 is in `2030-W01` and
  lands in `2030/`. UTC because the event segments already name their files
  in UTC, and because a week that depends on the phone's time zone would
  give two names to one week when the owner travels. The week turns over on
  Monday 00:00 UTC, an hour or two into Monday at home.
- The name is the week the backup was **taken** in, at the first
  opportunity of that week, usually Monday morning. It is not "the week's
  data up to Sunday".

`VaultPathPolicy` gains exactly this shape, for writing and for reading:
four segments, `backups`, the own device id, four digits, a name ending in
`.json.gz`. Another device's folder, a deeper path, another extension are
refused before anything is sent, as for events. The read is for D3's one
look only.

### D3 -- Create-only; "already there" is done once it is seen; not through the write queue

The upload is one `VaultTransport.createOnly`. Its answers:

- created (201): done;
- already exists (422, `VaultWriteOutcome.alreadyExists`): the week's file
  is in the vault -- **done, a success**, once one read of that path has
  found it. This is how a lost response heals: the upload landed, the
  answer did not, the next attempt finds the file;
- anything else: a failure (D4).

**A bare 422 is not believed.** The first plan was "422 means the week is
done". GitHub's reference lists 422 on this route as "validation failed,
or the endpoint has been spammed", not only "the path exists" (documented,
not observed by this project), and the event upload never believes a bare
422 either (`CreateOnlyFileUploader` reads the file back). For a backup the cost of believing it is the worst
one there is: every week recorded as done, "Last backup" showing a date,
and nothing in the vault. So after a 422 the uploader reads the path once
(`problemConfirming`): a file there means done; "not found" is a failure
shown as "Unexpected answer from GitHub (422)"; a read that fails (offline)
leaves the week open for the next attempt. The read happens only after a
422, so in practice after a lost answer: one request, at most the size of
one backup.

What is kept from the decision: the content is **not** compared. For an
event segment "already exists" must be told apart from a collision,
because the queue holds bytes that must not be lost. A backup has no such
bytes: whatever the existing file holds, next week's file holds everything
again. So the backup does not go through `DurableQueue` either: the queue
would keep a megabyte of base64 on disk, show a failed backup as "N events"
under "Not uploaded", and send week-old bytes when a retry finally works.
The archive is built fresh for every attempt instead.

409 (two commits racing on the branch) is avoided rather than handled: the
foreground runs the backup after the event delivery, in the same task.

### D4 -- When it runs, and the retry bounds

`VaultBackupService.runIfDue` (app) is called:

- on launch and on every return to the foreground, after
  `TrainingEventsService.drainNow`, unstructured, never awaited by a
  screen;
- in the existing background refresh (`BackgroundRefresh.run`), on a
  Garmin-connected install. That refresh is only scheduled while Garmin
  entries wait, so it is a bonus, not the schedule. No new background mode,
  identifier or entitlement.

It does nothing unless all of these hold -- the event upload's gate plus
the device id:

- the connection is on and configured, on a Garmin-connected install
  (`TrainingEventsService.isConnectionOn`);
- "Test connection" has succeeded once (a device id exists);
- VaultKit's request gate is open: a token, no loud block, no rate-limit
  pause.

Then the pure rule `VaultBackupSchedule.isDue(state, now)`:

1. no success is recorded for the current ISO week;
2. fewer than `maxAttemptsPerWeek` (5) counted failures this week;
3. the last attempt was at least `retryInterval` (1 hour) ago.

What counts as an attempt (`VaultBackupFailure.spendsAttempt`): a server
error, a conflict, an unexpected answer, a transport error other than "no
connection", a refusal by the path policy, an archive that could not be
built, an archive over the cap. What does **not** count: offline, a
rejected token, a rate limit, "not configured", an empty data set. Those
are not the upload's fault (the house rule of `DurableQueue`); the one-hour
interval alone keeps them from looping.

A week that ends without a success is skipped: the counter belongs to its
week and the next week starts at zero.

### D5 -- "Back up now": a second, time-stamped file

In a week without a file, "Back up now" writes the weekly name and that is
the week's backup. In a week that already has one it writes

```
<hub root>/backups/<deviceId>/<YYYY>/<YYYY>-W<ww>-<yyyymmdd>T<hhmmss>Z.json.gz
```

(the same UTC stamp the event segments use). If the weekly name turns out
to exist although the phone did not know (422, confirmed as in D3), the
week is recorded as done and the tap goes on to the time-stamped name.

Chosen over "this week is already backed up": the button is pressed before
something risky -- an update, a restore, a phone going to service -- and a
six-day-old file is no answer then. It costs one extra file, and only when
the owner asks. Manual taps are not rate-limited by the app; each one is a
commit he made on purpose.

Within a week the unsuffixed file is always the older one, so "newest per
device" is: the highest week, and in it the highest time stamp if any.

### D6 -- Size: what is in it, the estimate, the cap

The archive holds what an export holds, no more and no less:

| In | Out (already excluded by `BackupExclusions`) |
|---|---|
| closed food days, the standalone food log, custom foods, meal presets, favourites, usage history, serving defaults, the food cache | the Czech offline food index (large, re-downloadable) |
| weigh-ins, drinks, day notes, fasting history, local goals | the Garmin health cache (re-read from Garmin) |
| supplements: plan, limits, intake, barcode lookups | the diagnostics log |
| gamification: XP, achievements, challenges, records, journeys, bingo, boss, the training rewards | every `VaultKit/` file: device id, status, the cached plan, the write queue, the unsent training events, this upload's state |
| the last 120 days of day digests and activities | the Garmin and delete outboxes, the Siri donation ledger |
| preferences (themes, layout, reminders, goals, the vault connection's owner, name and branch) | the data mode, backup bookkeeping, developer switches |

There are no images and no logs in it. Three included stores are caches
that Garmin or a lookup could rebuild (day digests, activities, barcode
lookups; together about 15% of the bytes). They stay in: taking them out
would make the upload differ from an export, and a restore *replaces* --
it would delete those files on the phone and the trends built on them
until they were fetched again.

**Not in it, and worth knowing:** the morning check-ins, habit ticks, RPE
and plan edits. They are training events; their system of record is the
vault's `events/` folder, where they already are. The ones not uploaded
yet sit in `VaultKit/training-events.json`, which is device state and is
delivered by the event upload, not by a backup.

**Estimate.** No phone was measured. `measure.mjs` (in the session's
scratch folder, not committed) scaled the repository's synthetic store
fixtures to a daily user's counts, with every number randomised so the
compression is not flattered, built the container the way `encoded()`
does and compressed it at DEFLATE level 5:

| Use | Store files | Export (`.json`) | Uploaded (`.json.gz`) |
|---|---|---|---|
| 3 months | 1.2 MB | 1.6 MB | 0.3 MB |
| 1 year | 2.3 MB | 3.1 MB | 0.7 MB |
| 3 years | 5.3 MB | 7.1 MB | 1.6 MB |
| 5 years | 8.3 MB | 11.1 MB | 2.5 MB |

Read it as "a few hundred kilobytes a week now, under a megabyte for the
first year or two". The stores that grow without a cap are drinks,
supplement intake and the reward ledger. The real figure is on the phone
after the first backup (Settings > Vault > Last backup) and is tasks 7.2.

**Cap.** `VaultBackupSchedule.maxBytes` = 3 MiB of compressed bytes. Above
it nothing is sent, the attempt is recorded as "too large" with both
numbers, and Settings shows it. Three, because the model reaches it after
about five years of daily use and the request body (base64 again, for
GitHub's contents API) stays near 4 MB. Reaching it is the signal to trim
a store or to prune history, not to raise the number quietly.

**Cost in the vault.** Every weekly file stays in git history; compressed
files do not delta against each other. At 0.3 to 0.7 MB that is 15 to
35 MB a year of history, plus the working copy until old files are pruned
on the desk ("For the vault").

### D7 -- No secret leaves the phone

Read in the code:

- The Garmin OAuth tokens are in the Keychain (`GarminKit/TokenProvider`,
  `KeychainStore`), never in a file. No password is stored anywhere:
  sign-in is a web session.
- The vault token is in the Keychain (`VaultKit/VaultTokenStore`).
- The archive is built by `makeExportContainer`, which takes only files
  `BackupExclusions.includesFile` accepts -- `.json` under Application
  Support, minus the outboxes, `VaultKit/`, and any path component
  containing `token`, `oauth`, `cookie`, `credential` or `password` -- and
  then drops every file whose content carries an OAuth key or a GitHub
  token (`BackupSecretPolicy`). Preferences pass the same two filters;
  `garminAccountTokenFingerprint` falls to the name rule.
- What does travel and is not a credential: `garminAccountKey`, a SHA-256
  of the Garmin user name (it scopes the outboxes), and
  `vault.connection.v1`, the owner, name and branch of the vault
  repository -- inside that repository.

`VaultUploadArchiveTests` plants all of them in a data directory and reads
the uploaded bytes back: a token-named file, a file with an OAuth key
inside, a GitHub token in a store and in a preference, every `VaultKit/`
file, an outbox. A second test names the stores that must never be
uploaded (`vault.device-identity`, `vault.write-queue`, `vault.status`,
`vault.fetch-cache`, `vault.backup-upload`, the four outboxes, the
diagnostics log) and fails when the catalog stops excluding one of them.

A file dropped for its content is dropped whole (a custom-foods file with
a token pasted into a name is not uploaded at all) and named in
Diagnostics, as for an export.

### D8 -- The upload's own state is a device-local file

`VaultKit/backup-upload.json` (`VaultBackupState`, through
`VaultBackupStateStore` and `PersistedJSON` like every VaultKit store):
the last success (when, which week, path, size), the last attempt, the
week's counted failures, the last failure. It has a `StoreCatalog` entry
(`vault.backup-upload`, device only) and a fixture.

It is **not** in the backup. It says what *this phone* uploaded; restored
on another phone, or on this one from an older file, it would claim a week
is done that is not, or forget one that is. Living under `VaultKit/` it is
excluded by the directory rule already. Losing it costs one request: the
next attempt finds the week's file and records the week as done.

Disconnect does not clear it. It is history, and a reconnect to the same
repository should not upload the week twice.

### D9 -- Failures are quiet; the status is fed like the event upload feeds it

A failed backup never raises a banner. It is recorded in the state file,
shown under Settings > Vault > Backup with its time, and logged under
`vault` in Diagnostics.

The connection's status is touched exactly as `drainNow` touches it:

- a success (created or already there) records `.success`, which moves
  "Last sync";
- a rate limit records the pause, so every vault request waits;
- a rejected token (401, 403, 404 on the PUT) is **not** written into the
  status by the backup. It triggers the forced plan fetch the event upload
  uses (`TrainingEventsService.onAuthStop`), whose answer names the loud
  problem if there is one. A token that can read but not write must not
  block the plan.

### D10 -- A recent vault backup counts as the off-phone copy

`BackupReminderPolicy.shouldShow` takes `lastVaultBackupAt` beside
`lastExportAt`. The app writes it (`dataSafety.lastVaultBackupAt`, a key
backups already exclude by prefix) after every backup that reached the
vault. With the weekly backup working, the "Keep a copy of your data"
banner stays away; when it has not worked for 14 days the banner is back.
That makes the banner the loud signal of a stalled weekly backup, which D9
otherwise keeps quiet.

Settings > Data is unchanged: "Last export" is still the last export by
hand.

### D11 -- What the owner sees

Settings > Vault gets a "Backup" section between Status and Details:

- "Last backup": date and time, the size under it; "Never" before the
  first.
- "Last problem", with its time, while the last attempt failed.
- "Back up now", with a spinner; afterwards one line: "Backed up to the
  vault (412 KB)." or what stopped it.
- A footer: weekly, automatic, restored with Settings > Data > Import
  backup.

Details gains "Backups folder" under "Events folder".

## For the vault

Nothing has to run on the vault's side. This is what appears in the
repository and what the desk may do with it.

**Path** (relative to the repository root):

```
Sport/Training/_hub/backups/<deviceId>/<YYYY>/<YYYY>-W<ww>.json.gz
Sport/Training/_hub/backups/<deviceId>/<YYYY>/<YYYY>-W<ww>-<yyyymmdd>T<hhmmss>Z.json.gz
```

- `<deviceId>`: `ios-` + 8 lowercase hex, the same id as the phone's
  `events/<deviceId>/` folder. A reinstall or a new phone is a new id and a
  new folder.
- `<YYYY>`: ISO week-numbering year; `<ww>`: ISO week, 01 to 53; both in
  UTC.
- The first form is the automatic weekly file (at most one per week). The
  second is "Back up now" in a week that already had a file; its stamp is
  UTC.
- Commit message: `hub: <deviceId> backup <file name> (<n> bytes)`. Event
  commits read `hub: <deviceId> seq ...`.
- Files are created once and never changed or deleted by the app. The app
  reads one of its own files back only when GitHub answered a create with
  "already exists", to see that it is there.

**Format.** gzip (RFC 1952) of one UTF-8 JSON document, the app's export
container:

```
{ "manifest": { "schema": "garminfood.backup", "formatVersion": 1,
                "kind": "export", "createdAt": "<ISO 8601>",
                "appVersion": "<version (build)>",
                "files": [ { "path", "byteCount", "storeId", "storeVersion" } ] },
  "files": [ { "path": "<relative to Application Support>",
               "contents": "<base64 of the store file's bytes>" } ],
  "preferences": { "<key>": { "type": "...", "value": ... } } }
```

`manifest.createdAt` is when the backup was taken. Size: a few hundred
kilobytes, never above 3 MiB (3 145 728 bytes).

**Restore.** Get the newest file of the device onto the phone (the vault
folder in Files, or download it from the repository's web page), then
Settings > Data > Import backup, pick it, confirm the preview, close and
reopen the app. The compressed file is accepted as it is; unpacked
(`gunzip`) it is the same file "Export backup" writes. After a restore on
a new phone the Garmin sign-in and the vault token have to be entered
again, and the phone gets a new device id.

**What the desk could do later** (not needed for anything to work):

- list the newest backup per device and its age in the ingest report, and
  warn when the newest is older than, say, 21 days;
- prune: keep the newest 8 weekly files per device and one per quarter
  before that. Deleting a file in a commit frees the working copy on every
  clone; the bytes stay in history;
- ignore the folder everywhere else: nothing in it is an event, and the
  1 MiB segment limit of `events/` does not apply.

**What is in it that the vault may care about:** food, weight, water,
supplements, notes and preferences in the app's own store formats, not a
contract. Do not parse the stores on the desk; if a number is wanted in
the vault, it belongs in an event or a nutrition bridge file.

## Risks / Trade-offs

- **Nothing was compiled.** The gzip framing and the ISO week were checked
  with Node; the Swift is read against its declarations only. The first CI
  run is the compiler. The compression calls are the shapes
  `OfflineFoodIndex.swift` and its tests already compile.
- **The size estimate is a model.** If the real archive is much larger,
  the cap holds it back and Settings says so; the first on-phone number
  settles it (tasks 7.2).
- **A create request this large has not been observed.** The event
  segments stay under 900 KiB; a backup's request body can reach about
  4 MB. GitHub documents the contents API for far larger files, and the
  client's 20 s timeout is an idle timeout, not a total one -- but both are
  documented, not observed here. The first real backup shows it (tasks
  7.1); the fallback, should GitHub refuse the size, is a lower cap, and
  the failure would be visible in Settings as "Unexpected answer from
  GitHub (413)" or the like, never silent.
- **History grows by every file.** Accepted for a weekly cadence; pruning
  the working copy is the desk's (above). Rewriting history is not planned.
- **A background upload can be cut off** by iOS. Create-only makes that
  safe: either the file landed (the next attempt finds it) or it did not.
- **A restore brings back the week it was taken in.** Up to a week of
  phone-only data (drinks, closed days, supplement ticks, XP) can be lost
  between two backups; Garmin still holds the food and the weight. "Back
  up now" is the answer before anything risky.
- **A leaked token can read the backups.** They sit in the repository the
  token already reads; no new reach.

## Migration Plan

None. A new file appears under `VaultKit/` on the first attempt; an older
build ignores it, and a backup never contains it. The first foreground
after the update with a working connection uploads the first backup.

## Open Questions

- **The cap** is 3 MiB by the model. Say so if the first real backup is
  far from the estimate.
- **Pruning on the desk**: how many weekly files to keep is the owner's
  call ("For the vault" suggests 8 plus one per quarter).
- **The reminder (D10)**: a working weekly backup silences the export
  banner. Say so if the banner should keep asking for an export every 14
  days regardless.
- **Background refresh**: kept in because it costs one line. If backups at
  night on mobile data are unwanted, it comes out again.
