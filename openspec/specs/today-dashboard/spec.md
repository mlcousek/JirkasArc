# today-dashboard Specification

## Purpose
Define what the home screen's calorie figures mean (a Target that adds the day's active calories, the burned calories shown under it, a ring whose colour changes in steps with progress, the calories always leading the Today summary) and that the Profile header shows the owner's real name.

## Requirements

### Requirement: The home Target adds the day's active calories

The system SHALL show as the home-screen Target the account's base calorie
goal (Garmin `calorieGoal`) PLUS the selected day's active calories burned
(owner decision 2026-10-19, replacing the fixed Target of 2026-09-23), and
SHALL compute the ring's percentage, "kcal left" and the calorie "goal met"
judgement against that Target. The active calories are the app's own read
(see the next requirement), not Garmin's `adjusted*` goal; the adjusted goal
is used, unchanged, only when the payload has no base goal. Macro goals and
the per-meal targets SHALL stay the base values.

#### Scenario: A run raises the target

- **WHEN** the user burns 600 active kcal on a run and the base goal is 2300
- **THEN** the Target reads 2900 kcal and the ring percentage is consumed ÷ 2900

#### Scenario: Active calories unknown

- **WHEN** the day's active calories have not been read, or the read failed
- **THEN** the Target is the base goal alone

### Requirement: Active calories are shown under the Target

The system SHALL show the selected day's active calories burned under the
Target, saying they are included in it. The value comes from the
`activeKilocalories` field of
`GET /usersummary-service/usersummary/daily?calendarDate={date}`
(live-verified 2026-09-23). If that read fails, the system SHALL hide the line
without showing an error.

#### Scenario: Active calories shown

- **WHEN** Garmin reports 290 active kcal for today
- **THEN** the home screen shows "Includes 290 kcal burned today" under the Target

#### Scenario: Route unavailable

- **WHEN** the daily summary read fails
- **THEN** the active line is hidden and the rest of the card renders normally

### Requirement: The day's calories lead the Today summary

The system SHALL show the calorie card (ring, Target, what is left) first in
the Today summary in both experiences. On a training-plan day with a carb
band, the plan's carbs and protein SHALL be shown in a second card under it,
never in its place.

#### Scenario: A training day

- **WHEN** the training experience is on and today's plan day has a carb band
- **THEN** the calorie ring is shown first and the carbs and protein card under it

### Requirement: The calorie ring colour reflects progress in steps

The system SHALL colour the calorie ring by the percentage of the Target
eaten, using these steps:

| % of Target | Colour |
|---|---|
| under 50% | cool grey-blue |
| 50% to under 80% | orange |
| 80% to under 95% | yellow |
| 95% to 105% inclusive | green |
| over 105% up to 115% | orange |
| over 115% | red |

#### Scenario: Hitting the goal band

- **WHEN** the user has eaten 2250 kcal of a 2300 kcal Target (97.8%)
- **THEN** the ring is green

#### Scenario: Well over the goal

- **WHEN** the user has eaten 2700 kcal of a 2300 kcal Target (117%)
- **THEN** the ring is red

### Requirement: The Profile header shows the owner's real name

The system SHALL show Garmin's `fullName` in the Profile header, falling back
to `displayName` and then to "GarminFood". It SHALL never show a UUID-like
identifier when a full name is available.

#### Scenario: Account whose displayName is a UUID

- **WHEN** socialProfile returns displayName "f8c8e6e5-…" and fullName "Jiří Mlčoušek"
- **THEN** the Profile header reads "Jiří Mlčoušek"
