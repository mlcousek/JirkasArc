## ADDED Requirements

### Requirement: Deleting a synced entry is saved on the phone first

In Garmin-connected mode, deleting a food entry that is already in Garmin
SHALL be recorded durably on the phone and SHALL return without waiting for
any network request. The delete SHALL be delivered later with
`DELETE /nutrition-service/food/logs/{date}` and the body
`{ "logIds": [<logId>] }` (the route the app already called; last verified
2026-09-16 as modelled on a live-tested client, not yet exercised by this
project). No other route SHALL be used. In standalone mode a delete SHALL
keep removing the entry from the phone's own food log and SHALL queue
nothing.

#### Scenario: Deleting without a connection

- **WHEN** the phone is offline and the owner deletes a synced entry
- **THEN** no error is shown, the delete is in the queue, and no request has been made

#### Scenario: Surviving a relaunch

- **WHEN** a delete is queued and the app is closed and opened again
- **THEN** the delete is still in the queue with the same day and entry

#### Scenario: Standalone mode

- **WHEN** the phone is in standalone mode and the owner deletes an entry
- **THEN** the entry is removed from the phone's food log and the delete queue is empty

#### Scenario: Deleting an edit that has not been sent yet

- **WHEN** the phone is offline in Garmin-connected mode and the owner deletes an entry whose edit is still queued
- **THEN** the edit is cancelled, the delete of the original entry is in the queue, no request has been made and no error is shown

#### Scenario: A leftover queued edit in standalone mode

- **WHEN** the phone is in standalone mode and the owner deletes a row that is a queued edit of a Garmin entry
- **THEN** the edit is cancelled, the delete queue is empty and no request is made

### Requirement: A queued delete is retried, and "already gone" is success

The app SHALL deliver queued deletes on the same occasions as queued
entries (after a change, on returning to the foreground, in a background
refresh), after queued entries have been sent and re-read. A `404` SHALL
count as delivered. A `429` SHALL stop the delivery cycle and honour
`Retry-After`. A sign-in failure or a missing connection SHALL stop the
cycle without counting an attempt. Any other `4xx` except `408` SHALL give
up at once; any other failure SHALL be retried with backoff and SHALL give
up after five attempts. A background refresh SHALL stay scheduled while a
delete is still waiting, and SHALL NOT be kept scheduled by one that gave
up.

#### Scenario: The entry is already gone

- **WHEN** Garmin answers a queued delete with 404
- **THEN** the delete counts as delivered and is not retried

#### Scenario: Offline is not a failure

- **WHEN** three delivery cycles run without a connection
- **THEN** the delete is still waiting and its attempt count is 0

#### Scenario: A server error five times

- **WHEN** Garmin answers a queued delete with 500 on five cycles
- **THEN** the delete has given up and is not sent a sixth time

#### Scenario: A refused delete

- **WHEN** Garmin answers a queued delete with 403
- **THEN** the delete gives up after that one attempt

#### Scenario: Background refresh

- **WHEN** the only thing waiting is a queued delete
- **THEN** a background refresh is asked for

### Requirement: A queued delete belongs to one Garmin account

A queued delete SHALL be tied to the Garmin account signed in when it was
made and SHALL only ever be sent to that account. A delete of another
account SHALL stay in the queue, unsent. Signing out SHALL tie every delete
not yet tied to an account to the account signing out.

#### Scenario: Another account signs in

- **WHEN** a delete was queued under account A and account B is signed in
- **THEN** a delivery cycle sends nothing and the delete is still waiting

#### Scenario: The same account returns

- **WHEN** account A signs in again
- **THEN** the next delivery cycle sends the delete

### Requirement: The day shows what a queued delete means

While a delete is waiting, its entry SHALL stay in its meal marked
"Deleting…", SHALL NOT offer edit, move or duplicate, and its calories and
macronutrients SHALL be left out of the meal's and the day's totals. Once
Garmin has confirmed the delete the entry SHALL no longer be shown, also
before the day has been read again. A delete that gave up SHALL mark its
entry "Couldn't delete" and its calories and macronutrients SHALL count
again.

#### Scenario: Totals while waiting

- **WHEN** a day has entries of 300 and 200 kcal and the 200 kcal entry has a delete waiting
- **THEN** the day shows 300 kcal and the entry is marked "Deleting…"

#### Scenario: Confirmed before the day is re-read

- **WHEN** Garmin has confirmed the delete and the day shown is still the copy from before
- **THEN** the entry is not shown and the day shows 300 kcal

#### Scenario: Gave up

- **WHEN** the delete has given up
- **THEN** the entry is marked "Couldn't delete" and the day shows 500 kcal

### Requirement: A confirmed delete is checked against the day

After Garmin has answered a delete as done, the next read of that day SHALL
decide what the answer was worth. When the day no longer lists the entry,
the delete SHALL be finished and forgotten. When the day still lists the
entry more than five minutes after Garmin's answer, the app SHALL treat the
delete as one that gave up: the entry SHALL be shown again marked "Couldn't
delete", SHALL count in the totals, and SHALL offer "Retry" and "Keep
entry"; its error SHALL say that the day still lists the entry. A read
within five minutes of the answer that still lists the entry SHALL change
nothing. An entry that is still in Garmin SHALL NOT stay hidden once such a
read has happened.

#### Scenario: Still listed after the grace

- **WHEN** Garmin answered a delete as done (a 404 included) and a read of the day six minutes later still lists the entry
- **THEN** the entry is shown again marked "Couldn't delete" and the day's totals include it

#### Scenario: Still listed right after the answer

- **WHEN** a read of the day one minute after Garmin's answer still lists the entry
- **THEN** the entry stays hidden and the delete is still counted as confirmed

#### Scenario: No longer listed

- **WHEN** a read of the day no longer lists the entry
- **THEN** the delete is forgotten and the entry is not shown

### Requirement: A delete that gave up can be retried or dropped

A delete that gave up SHALL be marked on its entry and listed in the sync
queue with its last error, and both places SHALL offer "Retry" and "Keep
entry".
Retry SHALL make the delete wait again with a fresh attempt count. "Keep
entry" SHALL remove the delete from the queue, leaving the entry in Garmin
and on the day; it SHALL also be offered for a delete that is still
waiting, and SHALL be refused while that delete is being sent.

#### Scenario: Retry

- **WHEN** the owner taps Retry on a delete that gave up
- **THEN** the delete is waiting again with an attempt count of 0

#### Scenario: Keep entry

- **WHEN** the owner taps "Keep entry"
- **THEN** the queue no longer holds the delete and the entry counts in the day's totals

#### Scenario: Being sent right now

- **WHEN** "Keep entry" is tapped while that delete's request is in flight
- **THEN** the delete stays in the queue and the app says it is being sent
