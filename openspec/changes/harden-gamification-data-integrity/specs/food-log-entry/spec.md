## MODIFIED Requirements

### Requirement: A confirmed entry updates local usage ranking

Confirming an entry SHALL update the food catalog's local usage record for that food and serving, so that future quick-pick ranking reflects the newly logged entry. Each usage record SHALL name the logged entry it belongs to, and deleting or cancelling that entry SHALL remove exactly its record, so a deleted food no longer counts for streaks, challenges or variety. An identical food logged separately, and any record written before records named their entry, SHALL be left in place.

#### Scenario: Logging a food updates its ranking

- **WHEN** a food and serving are logged
- **THEN** the local usage record for that food and serving is updated with the current timestamp

#### Scenario: Deleting a logged food removes only its own usage record

- **WHEN** the same food, serving and amount are logged twice and the first entry is deleted
- **THEN** the first entry's usage record is removed and the second entry's record remains

#### Scenario: Editing an entry keeps one usage record that follows it

- **WHEN** a logged entry's amount is edited and the edited entry is then deleted
- **THEN** the entry had one usage record throughout, and deleting the edited entry removes it
