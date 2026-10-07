# challenges Specification

## Purpose
Offer short-horizon, achievable goals beyond the daily streak, drawn from a curated set of templates and evaluated entirely against the local log history.

## Requirements

### Requirement: One or two challenges are active at a time, drawn from a curated template set

The system SHALL maintain one or two active challenges at any time, selected from a fixed set of challenge templates, each with a locally-evaluable completion condition against the log history.

#### Scenario: No active challenge

- **WHEN** the app has no currently active challenge
- **THEN** a new one is selected from the template set and activated

### Requirement: Challenge progress is evaluated from the log history alone

The system SHALL evaluate a challenge's progress and completion purely from locally stored log entries and their existing metadata, without requiring a network call of its own.

#### Scenario: A goal-hitting challenge

- **WHEN** the active challenge requires hitting the day's nutrition goal on 4 of the last 5 nutrition-days
- **THEN** progress is computed directly from the local log history against goals already available locally

### Requirement: Completing a challenge is a rewarded, visible moment and triggers rotation

The system SHALL award XP on challenge completion, present a distinct completion moment (matching the levels capability's animated-moment requirement), and replace the completed challenge with a new one from the template set.

#### Scenario: A challenge's completion condition is met

- **WHEN** the active challenge's completion condition becomes true
- **THEN** the user sees a completion moment, XP is awarded, and a new challenge is activated

### Requirement: A challenge also rotates after a time window without completion

The system SHALL replace an active challenge that has not been completed within its defined time window, so a stale or unwinnable challenge does not persist indefinitely.

#### Scenario: A weekly challenge's window elapses uncompleted

- **WHEN** a challenge's defined time window elapses without its completion condition being met
- **THEN** it is replaced by a new challenge from the template set without awarding completion XP

### Requirement: Rotation favours curated and real-world challenges over number ladders

The system SHALL select the next long-running challenge by a deterministic
weighted pick in which hand-authored templates have weight 2, signal-based
real-world templates have weight 3, at most two tiers of each number-ladder
family (per macro or meal axis) have weight 1, and all other ladder tiers
have weight 0. Templates with weight 0 SHALL remain defined so that active
challenges, completion history and earned achievements referring to them
keep working. The last 8 activated templates SHALL be excluded from the
pick. A template whose data requirement (macros, water or activities) is not
met by any of the last 14 days SHALL NOT be picked.

#### Scenario: Ladder tier trimmed from rotation

- **WHEN** the rotation picks the next challenge
- **THEN** it never picks "log-streak-4" (a trimmed ladder tier)

#### Scenario: Same inputs, same pick

- **WHEN** the rotation is evaluated twice with the same time, history and signals
- **THEN** it picks the same template both times

#### Scenario: No water data

- **WHEN** no hydration data exists in the last 14 days
- **THEN** "Hydration Station" is not picked

#### Scenario: "Complete every challenge" stays achievable

- **WHEN** the owner has completed every template with non-zero rotation weight
- **THEN** the "complete every challenge" achievement unlocks, even though trimmed ladder tiers were never completed

### Requirement: Real-world challenges are evaluated from day signals

The system SHALL evaluate signal-based challenges from the per-day signals
aggregate within the challenge window, counting a day only when the
challenge's rule holds for that day, and SHALL show progress as days
satisfied out of days required.

#### Scenario: Something Fishy

- **WHEN** "Something Fishy" (fish on 2 days within 7) is active and the owner logs "Losos na grilu" on Tuesday and "Tuňákový salát" on Friday
- **THEN** the challenge completes on Friday and awards its XP once

#### Scenario: A day without macro data

- **WHEN** "Fibre Fanatic" is active and a day has an entry without known fibre
- **THEN** that day does not count toward the challenge and is not shown as failed
