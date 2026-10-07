# training-event-log Specification

## Purpose
Record what the owner does in the training experience as events in a local log, and deliver them to the vault in segments, durably and with guards.

## Requirements

### Requirement: Every training action is an event committed on the phone first

The system SHALL record every training action (morning check-in, habit
tick, session RPE, session note) as an immutable event appended to a local
log before the action returns, and SHALL NOT wait for the network on that
path. Each event SHALL carry a time-ordered unique id (UUIDv7), the
install's device id, a per-device sequence number that is never reused, the
producer's wall-clock time with its UTC offset, its type and a typed
payload that names the training day. A correction SHALL be a newer event of
the same kind.

#### Scenario: Check-in in airplane mode

- **WHEN** the owner taps Amber on Today with no network
- **THEN** the event is in the local log when the tap returns, Today shows Amber at once, and nothing waits for a request

#### Scenario: Sequence numbers survive a crash

- **WHEN** the app is killed right after reserving sequence number 12
- **THEN** the next event gets 13 or later, never 12 again

#### Scenario: Changing the light

- **WHEN** the owner taps Amber and then Green for the same morning
- **THEN** two events are recorded and Green, the later one, is what Today shows

### Requirement: The wire format is one versioned, deterministic envelope

The system SHALL serialise events as JSON Lines, one object per line with
sorted keys, a `\n` after every line, envelope version `v: 1`, and the
types `checkin.morning` `{date, light: green|amber|red, sessionId?,
option?}`, `habit.tick` `{date, habitId, done}`, `session.rpe` `{date,
sessionId, rpe 1-10, feel?}` and `session.note` `{date, sessionId, text of
1-2000 characters}`, writing optional keys as `null` when unknown. The
same events SHALL always produce the same bytes. Decoding SHALL ignore
unknown fields and SHALL read an unknown type without failing the file.
The envelope SHALL be defined in one source file and golden-tested against
a synthetic fixture and against the vault's own contract fixtures,
mirrored verbatim.

#### Scenario: Golden encode

- **WHEN** the synthetic events of the golden fixture are encoded
- **THEN** the bytes equal the fixture file exactly

#### Scenario: A newer vault fixture

- **WHEN** a fixture line has an extra field or the type `device.hello`
- **THEN** it decodes, the extra field ignored and the unknown type kept as unknown

### Requirement: Unsent events are delivered as immutable segments into the install's own folder

The system SHALL seal the unsent events into a segment file at
`events/<deviceId>/<yyyy>/<mm>/<yyyymmddThhmmssZ>-<firstSeq>.jsonl` with at
most 500 events, queue it in the durable vault write queue before marking
the events as sealed, and deliver it with a create-only write whose retry
can never create a second file or overwrite one. Delivery SHALL run on
launch and foreground, on backgrounding and shortly after an action, never
from a confirm path. It SHALL run only while the vault connection is
enabled, configured, has a token and a device id, and is not blocked by a
loud problem or a rate limit.

#### Scenario: Three ticks become one file

- **WHEN** the owner ticks three habits within a minute and leaves the app
- **THEN** one segment with three lines is created in his device's folder

#### Scenario: The response was lost

- **WHEN** a segment's create succeeded but the response never arrived, and the retry gets "already exists"
- **THEN** the app compares the blob SHA of the existing file with its own, finds them equal and marks the segment delivered

#### Scenario: Connection switched off

- **WHEN** the vault connection is off, or has no device id yet
- **THEN** no event is recorded, no segment is sealed and no request is sent

#### Scenario: Token revoked

- **WHEN** a segment upload answers 401
- **THEN** the loud vault banner appears, the cycle stops without spending an attempt, and the events stay queued

### Requirement: The phone's events show at once and stay shown until the vault has them

The system SHALL fold the phone's recent events (latest by sequence number
per day for the light, per day and habit for a tick, per session for RPE
and note) over the projection, so every screen shows them immediately, and
SHALL show whether each is only saved on the phone or already sent. A
local value SHALL win over the projection's value for the same key while
the event is kept (21 days). The phone SHALL NOT run the traffic-light
rules.

#### Scenario: Amber before the desk sync

- **WHEN** the owner checks in Amber and the projection still has no light for today
- **THEN** Today marks the A option as matching the morning check and reads "Saved on phone", later "Sent"

#### Scenario: Habit from the daily note

- **WHEN** the projection counts one "holds" for today and the phone has no tick
- **THEN** the "holds" toggle is on; after the owner turns it off on the phone, it shows off

### Requirement: The morning check-in carries the pain score in the contract's shape

`checkin.morning` SHALL carry `pains`, written as `null` when the pain was
not asked and otherwise as a list of `{site, score, note}` objects:
`site` one of `achilles-left`, `achilles-right`, `knee-left`, `knee-right`,
`other`; `score` a number 0-10 in steps of 0.5, written without a fraction
when whole; `note` a string of 1-200 characters or `null`. A payload with
a score off the half-step grid or out of range, or a blank or too long
note, SHALL be refused before anything is recorded. Reading an event, an
unknown site SHALL be read as `other`.

#### Scenario: Golden bytes

- **WHEN** the app encodes a check-in with the left Achilles at 5.5 with a note and the right knee at 1
- **THEN** the payload is `{"date":…,"light":"amber","option":"A","pains":[{"note":"…","score":5.5,"site":"achilles-left"},{"note":null,"score":1,"site":"knee-right"}],"sessionId":…}` byte for byte

#### Scenario: Not asked

- **WHEN** a Control records a check-in
- **THEN** its payload has `"pains":null`

#### Scenario: Off the grid

- **WHEN** a draft would record a score of 4.3
- **THEN** recording is refused and nothing is written

### Requirement: A later check-in keeps or replaces the day's pain like the vault

The phone's overlay SHALL take, per training day, the `pains` of the
latest check-in of that date that carries them: a later check-in without
`pains` keeps the earlier answer, and one with `pains`, `[]` included,
replaces it. The phone's answer SHALL win over the projection's `day.pains`
while the event is kept.

#### Scenario: Keep

- **WHEN** a check-in with `pains` is followed by one of the same date without
- **THEN** the day still shows the first check-in's pains, with the new light

#### Scenario: Replace with nothing

- **WHEN** a later check-in of the same date has `pains: []`
- **THEN** the day's pain is "none"
