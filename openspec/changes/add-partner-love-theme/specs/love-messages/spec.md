## ADDED Requirements

### Requirement: Each day has exactly one love message, different every day

The system SHALL assign to each calendar day from the pack's `startDate`
on exactly one daily message. The message SHALL be one not yet revealed,
drawn in a seeded order, so no message repeats while unrevealed ones
remain. When none remain, the system SHALL draw from favourites first,
then from all, and SHALL say so on the love card. Once a day's message has
been assigned it SHALL NOT change, including across re-plans, re-imports
and restores. No day SHALL have more than one love message.

#### Scenario: Thirty days, thirty messages

- **WHEN** a pack with 30 daily messages is used for 30 consecutive days
- **THEN** 30 different messages are revealed, one per day

#### Scenario: Assignment is fixed

- **WHEN** tomorrow's message has been planned and the pack is re-imported with 20 new messages today
- **THEN** tomorrow's notification still carries the message planned before the re-import

#### Scenario: Pool exhausted

- **WHEN** every daily message has been revealed and the user has three favourites
- **THEN** the next three days repeat those favourites and the love card says all messages are already known

### Requirement: The love message arrives at a random minute between 08:00 and 13:00, with the app closed

While the partner theme is active and notifications are allowed, the system
SHALL keep a local notification pending for each of the next 7 days. Each
SHALL fire at a minute from 08:00 to 12:59, every day of the week, derived
only from the pack seed and the date. When that minute is within 10
minutes of another planned reminder that day, it SHALL move to the next
free minute before 13:00. The title SHALL be "Pro {nickname} ❤️" and the
body that day's message. The day's picture SHALL be attached when it is
1 MiB or smaller.

#### Scenario: Same minute after a re-plan

- **WHEN** the app re-plans notifications three times on one day
- **THEN** today's love notification stays at the same minute with the same text

#### Scenario: Window

- **WHEN** the planned minutes for 1 000 consecutive dates are computed from one seed
- **THEN** every minute is at or after 08:00 and before 13:00, Saturdays and Sundays included, and they are not all equal

#### Scenario: App closed for five days

- **WHEN** the app is not opened for five days after the partner theme was activated
- **THEN** a love notification fired on each of those days

#### Scenario: Clash with breakfast

- **WHEN** the breakfast reminder is at 08:30 and the day's derived minute is 08:34
- **THEN** the love notification is planned for 08:41 or later and before 13:00

### Requirement: A message is revealed only once its time has come

The system SHALL reveal a day's message at its planned minute or when its
notification is opened, whichever comes first, and SHALL NOT show the text
of a day whose minute has not come. Before the minute, the love card SHALL
say the message arrives this morning. Revealing SHALL NOT depend on the
notification having fired.

#### Scenario: Opened early

- **WHEN** the app is opened at 07:30 and today's minute is 10:12
- **THEN** the love card says "Dnešní vzkaz dorazí dopoledne 💌" and no text of today's message is visible anywhere in the app

#### Scenario: Notifications denied

- **WHEN** notification permission is denied and the app is opened at 11:00 with today's minute at 10:12
- **THEN** today's message is shown on the love card and in the message box

### Requirement: The message box keeps every revealed message

The system SHALL list every revealed message in the message box ("Krabička
vzkazů"), newest first, with its date, and SHALL let the user mark and
unmark favourites and filter to favourites. Opening a love notification
SHALL open the message box at that day.

#### Scenario: Notification tap

- **WHEN** the user taps the love notification for 14 March
- **THEN** the app opens the message box scrolled to 14 March with that message revealed

### Requirement: Optional sealed scrolls and a countdown, shown only when the pack has them

When the pack has `openWhen` entries, the system SHALL offer each as a
sealed scroll that shows its title until opened and its text after. When
the pack has a `countdown`, the love card SHALL show the whole calendar
days left to it ("dnes" on the day, hidden after it). With no such
content, neither SHALL appear anywhere.

#### Scenario: Opening a scroll

- **WHEN** the user opens "Otevři, až jsi smutná"
- **THEN** its text is shown, the scroll is marked opened, and it stays readable afterwards

#### Scenario: Countdown

- **WHEN** the pack's countdown "Svatba" is 213 calendar days ahead
- **THEN** the love card shows "Do svatby zbývá 213 dní"

#### Scenario: No extras

- **WHEN** the pack has no `openWhen` entries and no countdown
- **THEN** no scroll list and no countdown are shown, and no achievement depending on them exists
