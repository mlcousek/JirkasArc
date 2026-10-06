## ADDED Requirements

### Requirement: The gate test is an event in the contract's shape

The app SHALL write the weekly gate test as a `test.gate` event with the
payload `{date, walkPain, hopPain, site, note}`: both scores numbers 0-10
in steps of 0.5, written without a fraction when whole; `site` one of the
morning pain's sites or `null`; `note` a string of 1-200 characters or
`null`. A score off the half-step grid or out of range, or a blank or too
long note, SHALL be refused before anything is recorded.

#### Scenario: Golden bytes

- **WHEN** the app encodes a gate test of 2030-10-23 with walking 1.5, hops 4, the left Achilles and a note
- **THEN** the payload is `{"date":"2030-10-23","hopPain":4,"note":"…","site":"achilles-left","walkPain":1.5}` byte for byte

#### Scenario: Off the grid

- **WHEN** a gate test would carry a hop score of 4.3
- **THEN** recording is refused and nothing is written

### Requirement: A session done without a watch is an event in the contract's shape

The app SHALL write "done without a watch" as a `session.done` event with
the payload `{date, sessionId, option, min, km, note}`: `option` `G`, `A`,
`R` or `null`; `min` whole minutes 1-6000 or `null`; `km` a number above 0
and at most 1000, written without a fraction when whole, or `null`; `note`
1-2000 characters or `null`. A payload outside these bounds SHALL be
refused before anything is recorded. Undoing it SHALL be an
`event.retracted` naming the event's id.

#### Scenario: A gym session

- **WHEN** the app encodes a gym session done in 45 minutes with a note and no distance
- **THEN** the payload is `{"date":…,"km":null,"min":45,"note":"…","option":null,"sessionId":…}` byte for byte

#### Scenario: A run with a whole distance

- **WHEN** the app encodes a run of 55 minutes and 10 km
- **THEN** the payload has `"km":10`, not `"km":10.0`

#### Scenario: Zero minutes

- **WHEN** a completion would carry `min: 0`
- **THEN** recording is refused and nothing is written

### Requirement: The fuel log is an event in the contract's shape

The app SHALL write what was eaten during a session as a `session.fuel`
event with the payload `{carbsG, date, durationMin, fluidMl, note,
sessionId}`: `carbsG` a number 0-2000 (0 is an answer), written without a
fraction when whole; `fluidMl` whole millilitres from 0 or `null`;
`durationMin` whole minutes 1-6000 or `null`; `note` 1-2000 characters or
`null`. A payload outside these bounds SHALL be refused before anything is
recorded.

#### Scenario: Golden bytes

- **WHEN** the app encodes 90 g of carbs and 750 ml for the long run of 2030-10-19, with a note and no duration
- **THEN** the payload is `{"carbsG":90,"date":"2030-10-19","durationMin":null,"fluidMl":750,"note":"…","sessionId":"2030-w42-sat-am"}` byte for byte

#### Scenario: Nothing eaten

- **WHEN** the owner logs 0 g
- **THEN** the event is recorded with `"carbsG":0`

### Requirement: A race result is an event in the contract's shape

The app SHALL write how a race ended as a `race.result` event with the
payload `{distanceKm, laps, note, raceId, reason, status, time}` and,
only when the owner filled a results time that differs from the elapsed
one, `officialTime`. `status` SHALL be `finished`, `dnf` or `dns`;
`reason` `stop-rule`, `injury`, `illness`, `other` or `null`; `time` and
`officialTime` strings of the form `h:mm:ss` with hours without a leading
zero; `distanceKm` above 0 or `null`, written without a fraction when
whole; `laps` a whole number from 0 or `null`. The event SHALL carry no
`date`. `officialTime` SHALL never be a copy of `time`. A payload outside
these bounds SHALL be refused before anything is recorded. Reading an
event, an unknown `status` SHALL make the line invalid and an unknown
`reason` SHALL be read as `other`.

#### Scenario: Golden bytes

- **WHEN** the app encodes a marathon finished in 3:24:10 over 42.2 km with a note
- **THEN** the payload is `{"distanceKm":42.2,"laps":null,"note":"…","raceId":"harvest-marathon-2030","reason":null,"status":"finished","time":"3:24:10"}` byte for byte, with no `officialTime` key

#### Scenario: Two times

- **WHEN** the owner enters an elapsed time of 21:31:23 and a results time of 19:57:19
- **THEN** the payload has both `"time":"21:31:23"` and `"officialTime":"19:57:19"`

#### Scenario: Not a time

- **WHEN** a result would carry the time `3h24` or `3:24`
- **THEN** recording is refused and nothing is written

### Requirement: The session rating carries pain during and after

`session.rpe` SHALL carry `pains` when the pain was asked: a list of
`{site, during, after}` objects, each score a number 0-10 in steps of 0.5
(without a fraction when whole). When the pain was not asked the `pains`
key SHALL be left out, and a score of one site that was not asked SHALL be
left out of its object. A score off the grid or out of range SHALL be
refused before anything is recorded. Reading an event, an unknown site
SHALL be read as `other`, and a missing or `null` `pains` as not asked.

#### Scenario: Golden bytes

- **WHEN** the app encodes an RPE of 7 with the left Achilles at 4 during and 6 after and the right knee at 1 after only
- **THEN** the payload is `{"date":…,"feel":3,"pains":[{"after":6,"during":4,"site":"achilles-left"},{"after":1,"site":"knee-right"}],"rpe":7,"sessionId":…}` byte for byte

#### Scenario: An RPE alone

- **WHEN** the owner taps an RPE number without touching the pain block
- **THEN** the payload has no `pains` key, and its bytes are the same as before this change

#### Scenario: Asked, nothing hurt

- **WHEN** the owner saves the pain block with every site removed
- **THEN** the payload has `"pains":[]`

### Requirement: The new events match the vault's own example lines

The app's encoding of the vault example's `test.gate`, `session.done`,
`session.rpe`-with-`pains`, `race.result` and `session.fuel` lines SHALL
be reproducible from those mirrored lines: decoding a mirrored line and
encoding it again SHALL give the bytes of the app's golden file, and the
same JSON object as the mirrored line, with no key added and none dropped.

#### Scenario: The six mirrored lines

- **WHEN** lines 25 to 28, 32 and 33 of the mirrored example are decoded and encoded again
- **THEN** each result equals the corresponding line of the app's golden file byte for byte, equals the mirrored line as a JSON object, and none decodes as an unknown type

### Requirement: The phone's overlay folds the new facts like the vault

The phone's overlay SHALL take the last gate test per date; per session
the `pains` of the last rating that carries them (a later rating without
`pains` keeps the earlier answer, one with `pains`, `[]` included,
replaces it); per session the last `session.done` and the last
`session.fuel` this phone has not retracted; and per race the last
`race.result` this phone has not retracted. A retracted fact SHALL leave
the fold. A race result named by a refused `race.result` outcome of the
projection SHALL be marked refused with the vault's reason.

#### Scenario: A corrected RPE keeps the pain

- **WHEN** a rating with pains is followed by a rating of the same session without
- **THEN** the session still shows the first rating's pains, with the new RPE

#### Scenario: Undo

- **WHEN** a session was marked done by hand and the owner undoes it
- **THEN** a retraction naming each of this phone's standing `session.done` events of that session is recorded and the session no longer counts as done by hand on the phone

#### Scenario: A refused result

- **WHEN** the projection's outcomes name this phone's `race.result` as refused
- **THEN** the overlay marks it refused and carries the vault's reason
