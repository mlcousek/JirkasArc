## ADDED Requirements

### Requirement: The load and gate fields of the projection are read tolerantly

The app SHALL read, from a projection of schema version 1: `athlete.gate`
(`null` = never tested); on every `week.actual` the fields `plannedRunKm`,
`unplannedRunKm`, `overPlanKm`, `longestRunKm`, `longestRunCapKm`, `hillM`
and `highSessions`; `flag` on an unplanned activity; `done.manual` and the
values `manual` of `done.source` and `done.matchedBy`;
`session.feedback.pains`; and top-level `notices`. Every one of them MAY
be absent, `null` or of an unexpected type without failing the file. A
missing number SHALL be read as unknown, never as 0; a verdict the vault
did not give SHALL be read as unknown, never as allowed; an unknown `flag`
or notice `kind` SHALL be kept as unknown; an unknown pain site SHALL be
read as `other`; a notice without a text SHALL be dropped.

#### Scenario: The example

- **WHEN** the vault's example projection is decoded
- **THEN** the gate is the test of 2030-10-23 with walking 1.5, hops 4, running allowed, speed not allowed, one week above 2 and not stale; W42's actual has 54.1 km planned, 6 km unplanned, 5.1 km over plan, a longest run of 17.5 km against a cap of 13.6 km, 460 m of climb and 0 hard sessions; one unplanned run is flagged over-plan; Monday's gym session is done with source manual and a manual record of 45 minutes; the tempo's feedback has two pain entries, the second with no score during

#### Scenario: The minimal file

- **WHEN** the vault's minimal projection is decoded
- **THEN** the gate is absent and there is one notice of kind `no-activities-since` without a date, with its English and Czech text

#### Scenario: An older file

- **WHEN** a projection from before 2026-10-01 is decoded
- **THEN** it decodes with no gate, no load fields, no flags, no manual records and no notices

#### Scenario: A data gap is not zero

- **WHEN** a week's `overPlanKm`, `longestRunCapKm` and `hillM` are `null`
- **THEN** each reads as unknown, and none as 0

### Requirement: Race results, the fuel log and the recovery window are read tolerantly

The app SHALL read `result` on every race of the season (`null` = nothing
recorded): `status`, `reason` and `source` as open enumerations, `time`
(the elapsed time) and `officialTime` (the organiser's, when another one)
as two separate nullable strings, `distanceKm`, `laps`, `note`, and
`goalReached` and `pr` as three-state values where `null` is "not known",
never "no". It SHALL read `fuel` on a session's feedback (`carbsG`,
`fluidMl`, `durationMin`, `gPerH`, `planGPerH`, `vsPlan`, `note`; a
feedback MAY carry a fuel log with no RPE) and `athlete.recovery`
(`raceId`, `day`, `of`, `rule`, `until`), which is a window only while
`1 ≤ day ≤ of`. Any of them MAY be absent, `null` or of an unexpected type
without failing the file. A race SHALL be looked up by its `id`, never by
its position in the list.

#### Scenario: Two results

- **WHEN** the vault's example projection is decoded
- **THEN** the 10K's result is finished with the elapsed time 0:46:03, the organiser's time 0:45:41, the goal not reached, a personal record and the source report; the marathon's is finished in 3:24:10 with no organiser's time, the goal reached, the personal record not known and the source event; the two races ahead have no result

#### Scenario: The organiser's time is never filled in

- **WHEN** a result has `officialTime: null`
- **THEN** the organiser's time reads as absent and is not copied from the elapsed time

#### Scenario: A fuel log

- **WHEN** the vault's example projection is decoded
- **THEN** the long run of 2030-10-19 has a fuel log of 90 g and 750 ml over 118 minutes, 46 g/h against 60 planned, below plan

#### Scenario: The recovery window

- **WHEN** the vault's example projection is decoded
- **THEN** the recovery window is day 10 of 14 after the marathon, under rule PM-SEQ-1, until 2030-10-27; in the minimal projection there is none

#### Scenario: Not a window

- **WHEN** `athlete.recovery` has `day: 0`
- **THEN** the app reads no recovery window
