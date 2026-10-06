## ADDED Requirements

### Requirement: Pain during and after a session is recorded with the rating

While pain mode is active, the session detail's "How did it feel?" SHALL
offer, for a session of today or an earlier day, a pain block: per site
one slider for pain during and one for pain after the session, each from 0
to 10 in steps of 0.5, with sites added and removed like the morning pain.
Save SHALL record a `session.rpe` event carrying the session's chosen RPE
and the `pains`; without a chosen RPE Save SHALL be disabled and the block
SHALL say that the effort comes first. The block SHALL list what is
recorded -- this phone's answer before the vault's -- with a score the
vault does not know shown as "–". Outside pain mode the block SHALL NOT be
shown. The vault's `session-pain` and `pain-not-settled` notes SHALL be
shown with the session's other notes.

#### Scenario: Recorded pain

- **WHEN** the vault publishes the left Achilles at 4 during and 6 after and the right knee at 1 after only
- **THEN** the block lists "Achilles (left): during 4/10 · after 6/10" and "Knee (right): during – · after 1/10"

#### Scenario: No effort chosen yet

- **WHEN** the session has no RPE
- **THEN** Save is disabled and the block says to choose the effort first

#### Scenario: Outside pain mode

- **WHEN** pain mode is not active
- **THEN** "How did it feel?" has no pain block

### Requirement: The morning step shows how yesterday's session pain settled

While pain mode is active, the morning pain step SHALL show, for every
site that has an "after" score in a session of the day before and a
morning score on the day, one line with both numbers ("yesterday after the
session: 3/10 → today: 1/10"). A site with only one of the two SHALL get
no line. The app SHALL NOT judge the two numbers.

#### Scenario: Both exist

- **WHEN** yesterday's session has the left Achilles at 6 after and this morning's score is 5.5
- **THEN** the step shows "Achilles (left) — yesterday after the session: 6/10 → today: 5.5/10"

#### Scenario: No morning score yet

- **WHEN** this morning's pain has not been answered
- **THEN** the step shows no such line

### Requirement: A session can be marked done without a watch

The session detail SHALL offer "Mark done (no watch)" for a session of
today or an earlier day that is neither done nor skipped, when the vault
connection can record -- for any sport, a gym session included. The sheet
SHALL ask for the option when the session has options (G, A or R, starting
at the one the morning light points at), the minutes, the kilometres for a
run, ride or walk, and an optional note, starting from the plan's own
targets, and Save SHALL record a `session.done` event. The session SHALL
show as done at once, and until the vault has read the event; after that
the plan alone decides. Undo SHALL be offered while this phone still holds
the event the session is done by, and SHALL retract every standing
`session.done` of this phone for that session. The week's sums SHALL NOT
be changed on the phone.

#### Scenario: A missed gym session

- **WHEN** the owner marks yesterday's missed mobility session done with 20 minutes
- **THEN** a `session.done` event with `min: 20` and no option and no distance is recorded, and the session reads "Done (logged by hand)"

#### Scenario: A traffic-light run

- **WHEN** the owner marks today's run done on an amber morning
- **THEN** the sheet starts at option A with option A's distance

#### Scenario: Undo

- **WHEN** the owner undoes a session marked done by hand
- **THEN** a retraction is recorded and the session reads as the plan has it again

#### Scenario: The vault did not count it

- **WHEN** the vault has read the event and the plan still shows the session as missed
- **THEN** the session reads missed and "Mark done (no watch)" is offered again

#### Scenario: A day ahead

- **WHEN** the session is planned for tomorrow
- **THEN** "Mark done (no watch)" is not offered

### Requirement: The fuel log is recorded for long sessions and races

The session detail SHALL offer a fuel log, on or after the session's day
and when the vault connection can record, for a race session, a session
with a fuel plan and a session planned or done at two hours or more: grams
of carbohydrate (0 is an answer), millilitres of fluid, an optional
duration in minutes and an optional note. Save SHALL record a
`session.fuel` event. The card SHALL show the vault's log -- the amounts,
grams per hour against the planned figure, and a neutral below / on /
above mark with a symbol and no judgement colour -- and SHALL ask for the
duration when the vault could not work out grams per hour. Until the vault
has read this phone's log, the card SHALL show the phone's amounts with
their delivery state and no verdict. The app SHALL NOT compute grams per
hour or the verdict.

#### Scenario: The vault's verdict

- **WHEN** the vault publishes 90 g and 750 ml, 46 g/h against 60 planned, below plan
- **THEN** the card shows "90 g carbs eaten · 750 ml fluid", "46 g/h of 60 g/h planned" and "Below plan"

#### Scenario: Not read yet

- **WHEN** the owner has just logged 120 g
- **THEN** the card shows "120 g carbs eaten", "Saved on phone" and that the plan answers after the next sync, with no verdict

#### Scenario: A short session

- **WHEN** a 50-minute session has no fuel plan and no log
- **THEN** no fuel log is offered

### Requirement: The new records need a vault connection that can record

The gate test, the session pain, "Mark done (no watch)", the fuel log and
the race result SHALL be offered only when the vault connection is on,
configured and has a device identity -- the same guard as the morning
check-in. Each SHALL be saved on the phone at once and delivered later;
none SHALL wait for the network.

#### Scenario: No vault connection

- **WHEN** the vault connection can not record
- **THEN** none of the five is offered, and what the plan publishes is still shown
