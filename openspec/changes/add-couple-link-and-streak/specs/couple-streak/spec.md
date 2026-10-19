## ADDED Requirements

### Requirement: A couple day counts only when both did their part

The system SHALL count a calendar day toward the couple streak when both
members have a day-done record for it. A member's day is done when at
least one food entry was logged that day. Both installs SHALL compute the
same streak from the same records.

#### Scenario: Both logged

- **WHEN** both members logged food on 14 March and the streak was 6
- **THEN** both phones show a couple streak of 7

#### Scenario: Only one logged, day over

- **WHEN** only one member logged on 14 March, no freeze is held, and it is now 16 March
- **THEN** the couple streak is 0 on both phones

### Requirement: A late report never breaks the streak

The system SHALL treat a day on which only one member is done as pending,
not missed, until the end of the following day. While pending it SHALL
show "čeká na partnera" and keep the current count.

#### Scenario: Partner's phone not synced yet

- **WHEN** it is 23:30 on 14 March, this member logged, and the partner's record for 14 March has not been read yet
- **THEN** the streak is unchanged and 14 March shows as waiting for the partner

#### Scenario: Arrives next morning

- **WHEN** the partner's record for 14 March is read at 07:00 on 15 March
- **THEN** 14 March counts and the streak increases by one

### Requirement: Couple freezes are earned and used automatically

The system SHALL earn one couple freeze at every 7th consecutive shared
day, hold at most 2, and use one automatically for a missed day that would
otherwise end the streak, oldest missed day first.

#### Scenario: Freeze covers a miss

- **WHEN** the streak is 9 with one freeze held and 10 March is missed
- **THEN** the freeze is used, the streak continues, and no freeze is held

#### Scenario: Cap

- **WHEN** a 21-day couple streak is reached without using a freeze
- **THEN** 2 freezes are held, not 3
