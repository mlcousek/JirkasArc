## ADDED Requirements

### Requirement: Partner achievements exist only while the partner theme is active

The system SHALL provide a set of partner achievements ("Svitky srdce")
that are shown and evaluated only while the partner theme is active, and
counted only from data dated on or after the pack's import date. Switching
the theme off SHALL hide the set and keep its unlocks. Switching it back
on SHALL show them again and unlock whatever the data earned meanwhile.
Secret partner achievements SHALL stay hidden until unlocked and SHALL use
the existing reveal moment.

#### Scenario: Not on another theme

- **WHEN** a pack is imported but Ocean is selected
- **THEN** the achievements screen shows no partner achievement and none unlocks

#### Scenario: No burst on day one

- **WHEN** the theme is activated on a phone with a 40-day streak that began before the import
- **THEN** "Jonin" (30-day streak) does not unlock until 30 streak days have passed since the import date

### Requirement: Partner achievements pay hearts, never XP

The system SHALL reward partner achievements with hearts ("srdíčka")
recorded in a ledger of earned and spent entries, SHALL derive the
balance from that ledger, and SHALL NOT add XP or change level, streak or
any existing achievement.

#### Scenario: XP unchanged

- **WHEN** "Chuninská zkouška" unlocks and pays 20 hearts
- **THEN** the heart balance rises by 20 and the XP total is the same as before the unlock

### Requirement: Hearts redeem the pack's coupons

When the pack has coupons, the system SHALL list them with their price in hearts,
SHALL allow redeeming a coupon only when the balance covers its price,
and on redemption SHALL record the spend and show the coupon as a dated,
stamped scroll that stays in a "Uplatněné" list.

#### Scenario: Not enough hearts

- **WHEN** the balance is 30 and a coupon costs 40
- **THEN** the coupon shows "Chybí 10 srdíček" and cannot be redeemed

#### Scenario: Redeemed

- **WHEN** a 40-heart coupon is redeemed with a balance of 55
- **THEN** the balance is 15 and the coupon appears in "Uplatněné" with today's date
