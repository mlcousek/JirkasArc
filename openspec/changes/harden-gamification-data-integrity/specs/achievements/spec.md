## ADDED Requirements

### Requirement: Lifetime statistics follow the logged entries, their day, and each goal day once

The lifetime ledger SHALL count one log per durable food entry, so a meal preset of N ingredients counts N logs while still earning one XP award. A log's calories SHALL be added to the nutrition day it was logged for, not the day it was confirmed. Each nutrition day SHALL count toward a macro's goal-hit total at most once, whatever order days are re-read in. Deleting a food SHALL NOT revoke an achievement, its unlock date, or XP already earned.

#### Scenario: A meal preset counts each ingredient

- **WHEN** a meal preset with three ingredients is confirmed
- **THEN** the lifetime log count grows by three and XP is awarded once

#### Scenario: A backdated log adds to its own day

- **WHEN** on 2 January a 900 kcal dinner is logged for 1 January, which already had 2000 kcal
- **THEN** 1 January's total is 2900 kcal and 2 January's total is unchanged

#### Scenario: Re-reading an older day does not count it again

- **WHEN** day A's goal status is recorded, then day B's, then day A's again
- **THEN** the goal-hit total counts day A once

#### Scenario: A deleted food keeps its badge

- **WHEN** a food that completed a streak badge is deleted
- **THEN** the badge stays unlocked with its original date
