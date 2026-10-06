## ADDED Requirements

### Requirement: A carb-load day has a carbohydrate target in grams

On a plan day whose fuel is a carb load, the day's carbohydrate target
SHALL be the plan's grams when it gives them; else the plan's single
grams-per-kilogram value multiplied by the body weight; else the plan's
`{ min, max }` grams-per-kilogram band multiplied by the body weight. The
body weight SHALL be the plan's, else the latest weigh-in. Without any of
these the day SHALL have no carbohydrate target and the food screen SHALL
keep its calorie summary. The phone SHALL NOT invent a value the plan does
not give.

#### Scenario: Grams in the plan

- **WHEN** the carb-load day gives 560 g and 8 g/kg
- **THEN** the target is 560 g

#### Scenario: Only grams per kilogram

- **WHEN** the carb-load day gives 8 g/kg, no grams, and the weight is 70 kg
- **THEN** the target is 560 g

#### Scenario: A band

- **WHEN** the carb-load day gives a band of 8 to 10 g/kg and the weight is 70 kg
- **THEN** the target is 560 to 700 g

#### Scenario: No weight known

- **WHEN** the carb-load day gives 8 g/kg, no grams, and no weight is known
- **THEN** the day has no carbohydrate target

### Requirement: The fuel card names the race and judges a single target

On a carb-load day the fuel card's title SHALL be "Carb-load day for
<race name>" when the plan names the race of that day and that race is in
the plan, and "Carb-load day" otherwise. With a single target the card
SHALL say "Below target" while the carbohydrates logged are under it and
"Target reached" from the target up, and SHALL NOT call any amount above
it too much. With a band it SHALL keep "Below range", "In range" and
"Above range".

#### Scenario: The race is known

- **WHEN** the carb-load day belongs to the race "Example 50K"
- **THEN** the title is "Carb-load day for Example 50K"

#### Scenario: The race is not in the plan

- **WHEN** the carb-load day names a race id the plan does not list
- **THEN** the title is "Carb-load day"

#### Scenario: Below a single target

- **WHEN** the target is 560 g and 400 g are logged
- **THEN** the card says "Below target"

#### Scenario: At and above a single target

- **WHEN** the target is 560 g and 560 g, then 640 g, are logged
- **THEN** the card says "Target reached" both times

#### Scenario: A band

- **WHEN** the target is 560 to 700 g and 600 g are logged
- **THEN** the card says "In range"

### Requirement: Race Day Fuel counts the plan's race days

In the training experience a day up to today with at least one food entry
SHALL count as a race day for "Race Day Fuel" when it is the date of a
race in the plan or carries the day-note `race` tag. Without a plan, and
in the food-first experience, only the `race` tag SHALL count, as before.
A day SHALL count once.

#### Scenario: A race of the plan

- **WHEN** the plan has a race on a past day with two entries and no `race` tag
- **THEN** that day counts as a race day

#### Scenario: No entries

- **WHEN** the plan has a race on a past day without any entry
- **THEN** that day does not count

#### Scenario: Food-first

- **WHEN** there is no plan and a day is tagged `race` with an entry
- **THEN** that day counts, and an untagged day does not

#### Scenario: Tagged and in the plan

- **WHEN** a race day of the plan is also tagged `race`
- **THEN** it counts once

### Requirement: Carb Loader is judged on the plan's carb-load days

In the training experience, for a race of the plan up to today that has
carb-load days in the plan, "Carb Loader" SHALL be earned when every one
of those days met its carbohydrate target, and SHALL NOT be earned from
that race otherwise. A race of the plan without carb-load days, and every
day without a plan, SHALL be judged as before: a day tagged `race` whose
two preceding days both met the carbohydrate goal.

#### Scenario: Both carb-load days met

- **WHEN** the plan's two carb-load days for a past race both met their target
- **THEN** Carb Loader is earned

#### Scenario: One day missed

- **WHEN** one of the plan's two carb-load days for a past race missed its target
- **THEN** Carb Loader is not earned from that race

#### Scenario: The race has not happened

- **WHEN** the plan's race is after today
- **THEN** it earns nothing yet

#### Scenario: No carb-load days in the plan

- **WHEN** a past race of the plan has no carb-load days, is tagged `race`, and its two preceding days met the carbohydrate goal
- **THEN** Carb Loader is earned by the tag rule
