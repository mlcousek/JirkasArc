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

- **WHEN** the day already has a pain answer and the owner says "Amber in Jirka's Arc"
- **THEN** the amber check-in is recorded without a pain answer and the day's pain answer is unchanged
