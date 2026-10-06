## ADDED Requirements

### Requirement: The weekly gate test is recorded on Today in pain mode

While pain mode is active, Today SHALL offer the weekly gate test for the
current training day: on Saturday and Sunday as a card of its own under
the training card, on other days as one link in the training card's pain
area that opens the same block. The editor SHALL have two sliders from 0
to 10 in steps of 0.5 -- pain when walking and pain on 20 single-leg hops
-- the tested site and an optional note, and Save SHALL record a
`test.gate` event for that day. Outside pain mode, and on a day that is
not the current training day, the gate test SHALL NOT be shown. Nothing
SHALL be recorded unless the vault connection can record.

#### Scenario: A weekend in pain mode

- **WHEN** pain mode is active and the current training day is a Saturday
- **THEN** the gate test is a card of its own under the training card

#### Scenario: A weekday in pain mode

- **WHEN** pain mode is active and the current training day is a Wednesday
- **THEN** the training card has one link that opens the gate test

#### Scenario: Outside pain mode

- **WHEN** pain mode is not active
- **THEN** no gate test is shown, whatever the last test in the plan says

#### Scenario: Saving

- **WHEN** the owner sets walking to 1.5 and hops to 4.5 and saves
- **THEN** a `test.gate` event with those two scores is recorded on the phone and the card shows the test as saved, with the note that the plan answers after the next sync

### Requirement: The gate verdict shown is the vault's

The gate card SHALL show the vault's verdict in words: the walking score
with whether running is allowed, and the hop score with whether speed,
hills and jumps are allowed or stay locked -- each with a symbol as well
as the words. When the vault says running is not allowed, the speed line
SHALL read locked whatever the vault says about speed. A verdict the vault
did not give SHALL show the score alone, never "allowed". A test the vault
calls stale SHALL be shown greyed with a line saying so. When the vault
counts more than two weekly tests in a row above 2/10, the card SHALL show
one neutral line that a physio check is advised. The app SHALL NOT work
out a verdict for a test the vault has not judged.

#### Scenario: Speed stays locked

- **WHEN** the vault's gate is hops 4.5/10 with speed not allowed
- **THEN** the card reads "Hops 4.5/10 — speed, hills and jumps stay locked"

#### Scenario: No running

- **WHEN** the vault says running is not allowed and speed is allowed
- **THEN** both lines read as locked

#### Scenario: Several weeks above 2

- **WHEN** the vault counts three weekly tests in a row above 2/10
- **THEN** the card shows that a physio check is advised; with two it does not

#### Scenario: A stale test

- **WHEN** the vault marks the test stale
- **THEN** the verdict lines are greyed and the card says the test is more than two weeks old

### Requirement: Today shows the week's load against the plan

For a day of a week whose `actual` carries load fields, Today's training
card SHALL show one load line from the vault's numbers: the week's run km
of its target, km over plan when above 0, unplanned km, the longest run of
its cap, the climb and the hard sessions. A value the vault does not know
SHALL be shown as "–", never as 0. Km over plan and a longest run above
its cap SHALL be marked as warnings with a symbol as well as the warning
tint, and SHALL never be worded as praise. The app SHALL NOT sum or
compare anything else.

#### Scenario: A week over its target

- **WHEN** the week has 60.1 of 55 km, 5.1 km over plan, 6 km unplanned, a longest run of 17.5 km against a cap of 13.6 km, 460 m of climb and 0 hard sessions
- **THEN** the line reads "Week 60.1 of 55 km · 5.1 km over plan · 6 km unplanned · longest 17.5 of 13.6 km cap · hills 460 m · hard sessions 0", with the over-plan part and the longest run marked as warnings

#### Scenario: A data gap

- **WHEN** the cap and the climb are `null`
- **THEN** the line shows "–" in their place

#### Scenario: An older plan

- **WHEN** the week's `actual` has none of the load fields
- **THEN** no load line is shown

### Requirement: Today shows the vault's notices and the recovery window

On the current training day, Today's training card SHALL show each of the
projection's `notices` as a quiet line in the app's language, an unknown
kind included. When the vault publishes a recovery window, it SHALL show
"Recovery day `day` of `of`" with the window's last day and the race's
name, reading the length from `of` and never assuming 14, and one generic
line of meaning chosen by the rule and the length; an unknown rule SHALL
show the day count only. The two-week wording SHALL NOT be shown beside a
7-day window. The recovery window SHALL NOT block or change any session.

#### Scenario: Nothing synced for days

- **WHEN** the projection carries a `no-activities-since` notice
- **THEN** its text is shown at the top of the training card in the app's language

#### Scenario: Day 10 of 14

- **WHEN** the recovery window is day 10 of 14 until 27 Oct
- **THEN** Today reads "Recovery day 10 of 14 · until 27 Oct"

#### Scenario: A week after a race that ended early

- **WHEN** the recovery window is day 2 of 7
- **THEN** Today reads "Recovery day 2 of 7" and does not show the two-week wording
