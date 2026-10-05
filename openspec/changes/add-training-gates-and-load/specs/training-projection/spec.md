## ADDED Requirements

### Requirement: The load and gate fields of the projection are read tolerantly

The app SHALL read, from a projection of schema version 1: `athlete.gate`
(`null` = never tested); on every `week.actual` the fields `plannedRunKm`,
`unplannedRunKm`, `overPlanKm`, `longestRunKm`, `longestRunCapKm`, `hillM`
and `highSessions`; `flag` on an unplanned activity; `done.manual` and the
values `manual` of `done.source` and `done.matchedBy`;
`session.feedback.pains`; and top-level `notices`. Every one of them MAY
be absent, `null` or of an unexpected type without failing the file. A
missing number SHALL be read as unknown, never as 0; an unknown `flag` or
notice `kind` SHALL be kept as unknown; an unknown pain site SHALL be read
as `other`.

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
