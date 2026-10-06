## ADDED Requirements

### Requirement: Race rewards are released from the vault's published result

The facts the training rewards are built on SHALL read a race's outcome
from the vault's published `season.races[].result`: `status` (`finished`,
`dnf`, `dns`) as the outcome, `reason` equal to `stop-rule` as "a stop
rule ended it", and `goalReached` and `pr` as three-state values. A reward
that needs "goal reached" or "personal record" SHALL be released only on
`true`; `null` SHALL be read as "not known", never as "no". Whether the
race's fuel plan was followed SHALL be read from the vault's verdict on
the race session's fuel log (`on` = followed; `below` or `above` = not; no
verdict = not known). This phone's own `race.result` that the vault has
not published, and one the vault refused, SHALL release nothing. Building
the facts again from the same projection SHALL give the same facts, so a
reward keyed by its race is granted once.

#### Scenario: A finished race with its goal reached

- **WHEN** the projection publishes a race as finished with `goalReached: true` and `pr: null`
- **THEN** the facts say finished and goal reached, and say nothing about a personal record

#### Scenario: A wise call

- **WHEN** the projection publishes a race as not finished with the reason `stop-rule`
- **THEN** the facts say the race was stopped by the rule

#### Scenario: Not published yet

- **WHEN** this phone has recorded a finish the vault has not published
- **THEN** the facts carry no outcome for that race

#### Scenario: Read twice

- **WHEN** the same projection is read twice
- **THEN** the facts are equal, and no race reward is granted a second time

#### Scenario: The fuel plan

- **WHEN** the race session's fuel log has the vault's verdict `on`
- **THEN** the facts say the fuel plan was followed; with `below` they say it was not; without a log they say nothing
