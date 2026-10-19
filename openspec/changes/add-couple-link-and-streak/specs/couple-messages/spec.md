## ADDED Requirements

### Requirement: Pokes and notes are sent to the partner in order

The system SHALL let a paired user send a poke chosen from preset kind
lines, at most 3 per day, and a note of at most 280 characters. Each SHALL
be written as the next numbered inbox item and delivered in order. The
receiving install SHALL read items from its last seen number until one is
missing, and SHALL never show an item twice.

#### Scenario: Fourth poke

- **WHEN** the user has sent 3 pokes today and taps "Šťouchnout" again
- **THEN** the button says the day's pokes are used up and nothing is sent

#### Scenario: Two notes, read later

- **WHEN** two notes are sent while the partner is offline and the partner's app then refreshes
- **THEN** both notes appear in the order sent, each once

### Requirement: Coupon redemptions and partner achievements reach the partner

When a paired user with the partner theme redeems a coupon or unlocks a
partner achievement, the system SHALL send it as an inbox item. The
receiving install SHALL show it as a notification and in its partner
history.

#### Scenario: Coupon on his phone

- **WHEN** she redeems the coupon "Večeře podle tvého výběru"
- **THEN** after his next refresh his phone notifies that she redeemed it, and Settings > Partner lists it with the date

### Requirement: Couple achievements join the partner set

The system SHALL add to the partner achievements, while paired: a 7-day
("Tým 7"), 30-day ("Spojená srdce") and 100-day ("Hokage lásky") couple
streak; both members logging all three main meals on the same day 5 times
("Synchronizovaná mise"); and sending a poke before 09:00 on 7 days
("Ranní pozdrav"). Each SHALL pay hearts like the other partner
achievements.

#### Scenario: Team 7

- **WHEN** the couple streak reaches 7 on her phone with the partner theme active
- **THEN** "Tým 7" unlocks with its reveal and its hearts are added
