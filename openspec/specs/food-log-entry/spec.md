# food-log-entry Specification

## Purpose
Turn a chosen food and serving into a confirmed, durable log entry — with a meal type and date — and hand it to the sync layer, completing the flow every fast-entry surface in this project ultimately triggers.

## Requirements

### Requirement: Confirming an entry commits it without waiting on the network

The system SHALL commit a food entry (food, serving, quantity, meal type, date) to durable local storage as soon as the user confirms it, and MUST NOT require network connectivity to complete the confirmation.

#### Scenario: Confirming an entry with no connectivity

- **WHEN** the user confirms a food entry while offline
- **THEN** the entry is committed locally and the confirm screen completes immediately

#### Scenario: Confirming an entry with connectivity

- **WHEN** the user confirms a food entry while online
- **THEN** the confirm screen completes without waiting for the Garmin delivery to finish

### Requirement: A confirmed entry is handed to sync in the same action that commits it

The system SHALL enqueue a confirmed entry for delivery, via the sync capability's per-process outbox, as part of the same action that commits the entry locally, so that no confirmed entry can exist without a corresponding delivery obligation.

#### Scenario: An entry is confirmed

- **WHEN** a food entry is confirmed
- **THEN** it exists simultaneously in local storage and in the delivery queue

### Requirement: A confirmed entry updates local usage ranking

Confirming an entry SHALL update the food catalog's local usage record for that food and serving, so that future quick-pick ranking reflects the newly logged entry.

#### Scenario: Logging a food updates its ranking

- **WHEN** a food and serving are logged
- **THEN** the local usage record for that food and serving is updated with the current timestamp

### Requirement: Meal type and date default sensibly but remain editable

The system SHALL default the meal type based on time of day and the date to today, and SHALL allow the user to change either before confirming, so that a late log for an earlier meal or an earlier day is possible without contorting the flow.

#### Scenario: Logging at a typical mealtime

- **WHEN** the user logs a food during a typical breakfast, lunch or dinner window
- **THEN** the corresponding meal type is pre-selected

#### Scenario: Logging a meal after the fact

- **WHEN** the user changes the date or meal type before confirming
- **THEN** the entry is recorded against the selected date and meal type, not the current moment

### Requirement: A logged food's amount and meal can be edited

The system SHALL let the user change the quantity of a logged food, and move
it to another meal, from the entry's swipe or context actions. Garmin has no
edit route, so the change SHALL be delivered as a replacement: the corrected
entry is created with `PUT /nutrition-service/food/logs` (confirmed
2026-09-16), and only after that succeeds is the old entry deleted with
`DELETE /nutrition-service/food/logs/{date}` (live-tested by garmin_mcp; in use
by this app). The edited value SHALL show immediately, without waiting on the
network.

#### Scenario: Change the amount

- **WHEN** the user edits a logged "Rohlík, 1 piece" to 2 pieces
- **THEN** the entry shows 2 pieces immediately, marked pending
- **AND** after sync, Garmin has one Rohlík entry of 2 pieces and no 1-piece entry

#### Scenario: Delete step fails after the create succeeded

- **WHEN** the corrected entry was created but deleting the old one fails
- **THEN** the old entry's removal stays queued and is retried with backoff
- **AND** the pending removal is visible in the sync queue, so the food is never lost and the duplicate is never silent

#### Scenario: Move to another meal

- **WHEN** the user moves an entry from Lunch to Snacks
- **THEN** it appears under Snacks immediately and is removed from Lunch after sync

### Requirement: An entry can be duplicated

The system SHALL let the user duplicate a logged entry into the same meal
with the same food, serving and quantity.

#### Scenario: Second coffee

- **WHEN** the user duplicates a logged coffee
- **THEN** a second, identical coffee entry is logged to the same meal

### Requirement: A past meal can be copied

The system SHALL let the user copy the items of a meal from a previous day
into the same meal today. The user first sees a preview in which individual
items can be deselected.

#### Scenario: Same breakfast as yesterday

- **WHEN** the user chooses "Copy from… → Yesterday's breakfast" and confirms all 3 items
- **THEN** those 3 foods are logged to today's breakfast with their original servings and quantities

#### Scenario: Quick-add item cannot be copied

- **WHEN** yesterday's breakfast contains a calories-only quick-add entry
- **THEN** the preview marks it as not copyable and copies the rest
