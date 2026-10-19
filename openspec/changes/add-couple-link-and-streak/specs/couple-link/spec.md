## ADDED Requirements

### Requirement: Two installs pair in person through a QR code

The system SHALL let one install show, after device authentication, a QR
code containing the couple hub repository, its token, the couple id and
both member ids. It SHALL let the other install scan it, store the token in
its own Keychain, create its `member.json` and test the connection.
Pairing SHALL work on standalone and Garmin-connected installs alike, and
SHALL NOT use or change the vault connection.

#### Scenario: Standalone phone pairs

- **WHEN** a standalone install scans the pairing QR and the test succeeds
- **THEN** Settings > Partner shows "Propojeno" with the partner's name and no Garmin or vault request was sent

#### Scenario: QR needs Face ID

- **WHEN** the user opens "Propojit" and cancels device authentication
- **THEN** no QR code is shown

### Requirement: Each install writes only its own couple files

The system SHALL refuse, before any request, every couple-hub write outside
the install's own member folder (`member.json`, `days/<yyyy>/<date>.json`,
`days/<yyyy>/<date>.b.json`, `inbox/<8-digit seq>.json`), and every read
outside the two members' folders with those shapes. Writes SHALL be
create-only and queued durably when offline.

#### Scenario: Partner's folder

- **WHEN** a write to the partner's `days/2030/2030-03-14.json` is attempted
- **THEN** it is refused with no request sent

#### Scenario: Offline day done

- **WHEN** the day's first food entry is logged with no network
- **THEN** the day-done file is queued and created on the next refresh with a connection

### Requirement: Only the agreed facts leave the phone

The system SHALL send only: the date and time a day was done, whether all
three main meals were logged, the level, unlocked partner achievements, pokes, notes and
redeemed coupons. It SHALL NOT send food names, amounts, calories, weight,
active calories, water amounts, fasting, supplement or health data.

#### Scenario: Day-done file content

- **WHEN** a day-done file is built for a day with 2 140 kcal logged
- **THEN** its fields are only `date`, `doneAt` and `allMeals`, and no number of calories appears in it

### Requirement: The partner's updates are read on foreground, periodically and in background refresh

The system SHALL read the partner's last 8 days and new inbox items when the
app comes to the foreground, every 2 minutes while it stays in the
foreground, and during background refresh. It SHALL turn each new inbox
item into one local notification. A rejected token SHALL be shown loudly in
Settings > Partner and on Today. Offline and rate limits SHALL only show the
last successful read time.

#### Scenario: Poke while closed

- **WHEN** the partner sends a poke while this app is closed and a background refresh later runs
- **THEN** one notification with the poke's text is delivered, and opening the app does not deliver it again

#### Scenario: Token revoked

- **WHEN** the couple hub answers 401
- **THEN** Settings > Partner and Today say the partner link stopped working, with "Propojit znovu"

### Requirement: Unpairing removes the link from this phone

The system SHALL, on confirmed unpairing, delete the couple token and the
local couple state from this install, stop all couple requests, and leave
the couple hub's files untouched.

#### Scenario: Unpaired

- **WHEN** the user confirms "Zrušit propojení"
- **THEN** no further couple request is sent and the couple streak is no longer shown
