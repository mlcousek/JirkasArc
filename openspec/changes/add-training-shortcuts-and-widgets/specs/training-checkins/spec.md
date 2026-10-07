## ADDED Requirements

### Requirement: A check-in from a shortcut can carry one pain score

The check-in shortcut SHALL accept an optional pain score from 0 to 10 and
an optional pain site. When a score is given the recorded `checkin.morning`
SHALL carry one pain entry with that score, rounded to the nearest half
step, for the given site or, without one, for the first site the pain step
on Today would offer; that answer replaces the day's earlier pain answer.
When no score is given the check-in SHALL carry no pain answer, so an
earlier one is kept. A score outside 0 to 10 SHALL record nothing. A pain
site given without a score SHALL record nothing either and SHALL be
answered with a sentence saying the score is needed: it is never dropped
behind a confirmation. The lock-screen Controls and the Home Screen
check-in widget SHALL keep sending the light only.

#### Scenario: Light and score

- **WHEN** a shortcut runs the check-in with Green, pain score 3 and no site, and no Achilles site was ever scored
- **THEN** `checkin.morning {light: green, pains: [{site: achilles-left, score: 3}]}` is recorded and the confirmation names the score and the site

#### Scenario: The site scored last

- **WHEN** the latest earlier day with a pain answer scored the right Achilles, and the shortcut runs with pain score 2 and no site
- **THEN** the recorded entry is for the right Achilles

#### Scenario: Not a half step

- **WHEN** the shortcut runs with pain score 4.3
- **THEN** the recorded score is 4.5

#### Scenario: Out of range

- **WHEN** the shortcut runs with pain score 12
- **THEN** nothing is recorded and the answer says the score must be between 0 and 10

#### Scenario: A site without a score

- **WHEN** the shortcut runs with pain site "Knee (left)" and no pain score
- **THEN** nothing is recorded and the answer says a pain site needs a pain score

#### Scenario: No score keeps the earlier answer

- **WHEN** the day already has a green check-in with a pain answer and the owner says "Amber in Jirka's Arc"
- **THEN** the amber check-in is recorded without a pain answer and the day's pain answer is unchanged

### Requirement: A repeated check-in from outside Today records nothing new

The vault takes the last `checkin.morning` of a day for its light, session
and option. So a check-in from a lock-screen Control, the Home Screen
check-in widget or the check-in shortcut SHALL first look at this phone's
own check-in for that training day (its events not yet dropped from the
local log). When that check-in has the same light and the request carries
no pain score, the system SHALL record nothing and SHALL answer that the
check-in is already recorded. When the light is the same and a pain score
is given, the system SHALL record a check-in that carries the earlier
check-in's session and option unchanged, plus the pain entry. When the
light differs, or this phone holds no check-in for the day, the check-in
SHALL be recorded with the day's session and the light's own option.

#### Scenario: The widget tapped twice

- **WHEN** the owner taps Amber on the check-in widget twice in a row
- **THEN** one amber check-in is recorded, and the second tap records nothing

#### Scenario: The same light after a check-in on Today

- **WHEN** today's check-in is amber and the owner activates the amber Control
- **THEN** nothing is recorded and the answer says the check-in is already recorded

#### Scenario: The same light with a pain score

- **WHEN** today's check-in is amber and a shortcut runs the check-in with Amber and pain score 2
- **THEN** a check-in is recorded with the earlier check-in's session and option and one pain entry of 2

#### Scenario: Another light

- **WHEN** today's check-in is amber and the owner taps Green on the widget
- **THEN** a green check-in is recorded with the day's session and green's own option

#### Scenario: An out-of-range score on a repeat

- **WHEN** today's check-in is amber and a shortcut runs the check-in with Amber and pain score 12
- **THEN** nothing is recorded and the answer says the score must be between 0 and 10
