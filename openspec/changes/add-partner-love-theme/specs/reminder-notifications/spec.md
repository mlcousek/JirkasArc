## ADDED Requirements

### Requirement: Notification texts follow the partner theme

While the partner theme is active, the system SHALL use Czech partner-theme
texts for every notification it schedules (meal, streak-at-risk, daily
challenges, fasting, habits, and the title of supplement reminders, whose
body keeps the supplement name). It SHALL choose among several variants
per kind in a way that is stable for the day. It SHALL NOT change when, or
whether, any reminder is scheduled. When the theme stops being active,
the next re-plan SHALL replace the pending texts with the standard ones.

#### Scenario: Breakfast with the theme

- **WHEN** the breakfast reminder is on and the partner theme is active
- **THEN** the pending breakfast request carries a partner-theme text, at the same time it would fire without the theme

#### Scenario: Stable text

- **WHEN** the app re-plans twice on the same day with the theme active
- **THEN** no pending request is replaced only because its text changed

#### Scenario: Theme switched off

- **WHEN** the user switches from the partner theme to GF Teal and the app re-plans
- **THEN** every pending reminder carries its standard text and no love notification is pending

### Requirement: The love notification has priority within the pending limit

The system SHALL keep at most 60 of its own requests pending. When the
plan exceeds that, it SHALL keep the love notifications for the next 7 days
and today's requests first, and drop the furthest days of the other kinds
first.

#### Scenario: Everything switched on

- **WHEN** every reminder kind, fasting, habits and four supplements are enabled with the partner theme active
- **THEN** at most 60 requests are pending, and all 7 love notifications are among them
