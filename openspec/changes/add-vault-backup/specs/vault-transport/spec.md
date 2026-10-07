## MODIFIED Requirements

### Requirement: The app may write only into its own events folder and read only its allowed files

The system SHALL refuse, before any network request, every write whose
normalised hub-relative path is neither under `events/<ownDeviceId>/` with
a `.jsonl` extension nor exactly
`backups/<ownDeviceId>/<four digits>/<name>.json.gz`, and every read
outside `projection/*.json`, its own events folder and that same backup
file shape. Paths containing empty, `.` or `..`
segments, backslashes, percent-encoding, control characters or a device id
other than this install's SHALL be refused, not corrected. The hub root is
`Sport/Training/_hub` in the vault repository.

#### Scenario: Another device's folder

- **WHEN** a write to `events/ios-00000000/2026/10/x.jsonl` is attempted on an install whose id is `ios-7f3a91c2`
- **THEN** it is refused with no request sent, and an error is logged

#### Scenario: Traversal attempt

- **WHEN** a write to `events/ios-7f3a91c2/../../projection/projection.v1.json` is attempted
- **THEN** it is refused with no request sent

#### Scenario: Reading a daily note

- **WHEN** a read of any path outside `projection/`, the install's own events folder and the install's own backup files is attempted
- **THEN** it is refused with no request sent

#### Scenario: The install's own backup file

- **WHEN** a write to, or a read of, `backups/ios-7f3a91c2/2030/2030-W42.json.gz` is attempted on the install `ios-7f3a91c2`
- **THEN** it is allowed

#### Scenario: Anything else under backups

- **WHEN** a write to, or a read of, `backups/ios-00000000/2030/2030-W42.json.gz`, `backups/ios-7f3a91c2/2030-W42.json.gz`, `backups/ios-7f3a91c2/2030/extra/2030-W42.json.gz` or `backups/ios-7f3a91c2/2030/2030-W42.json` is attempted on the install `ios-7f3a91c2`
- **THEN** it is refused with no request sent

### Requirement: Vault state in backups is limited to the connection settings

The system SHALL exclude the device identity, the vault status, the fetch
cache, the write queue and the backup upload's own state from every
snapshot, export and vault backup, SHALL include the connection settings
(enabled, owner, name, branch), and SHALL treat any file content starting
with a GitHub token prefix as a secret that makes the file excluded. Every
new vault store file SHALL have a committed fixture loaded through the
real store in CI.

#### Scenario: Snapshot contents

- **WHEN** a daily snapshot is taken on a connected install
- **THEN** it contains `vault.connection.v1` and none of `VaultKit/device-identity.json`, `status.json`, `fetch-cache.json`, `cache/`, `write-queue.json` or `backup-upload.json`

#### Scenario: A store without a fixture

- **WHEN** a developer adds a VaultKit store file without a fixture
- **THEN** the store-coverage test fails and names the file
