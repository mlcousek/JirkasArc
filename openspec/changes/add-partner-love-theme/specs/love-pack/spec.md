## ADDED Requirements

### Requirement: A love pack is imported from a file and unlocks the partner theme

The system SHALL import a `love-pack` version 1 file (extension `.arclove`)
opened from Files, AirDrop or Settings > Appearance > "Import love pack…".
It SHALL validate the whole file before changing anything, and on success
SHALL store its texts and pictures on the phone and make the partner theme
selectable. With no valid pack stored, the system SHALL NOT show the
partner theme, the love card, the message box or any partner achievement
anywhere.

#### Scenario: AirDropped pack

- **WHEN** a valid `.arclove` file with 30 daily messages and 5 pictures is AirDropped to the phone and opened in the app
- **THEN** the app shows "30 vzkazů, 5 obrázků" with "Importovat", and after confirming, the partner theme appears in Settings > Appearance

#### Scenario: No pack

- **WHEN** the app runs with no pack ever imported
- **THEN** Settings > Appearance lists only the 13 built-in themes and no love card is in the layout editor

### Requirement: An invalid pack is refused with a reason and changes nothing

The system SHALL refuse a file larger than 40 MiB before parsing it. It
SHALL also refuse a file that:

- is not valid JSON, or has another format or version;
- lacks `packId`, `nickname`, `startDate`, `seed` or a non-empty `daily`
  list;
- repeats an `id` within a list;
- has a text longer than 600 characters or a list longer than 2 000
  items;
- has more than 80 pictures, or a picture that is not PNG or JPEG, is
  larger than 2 MiB, or is more than 4096 px on a side;
- has a picture whose `slots` name an unknown slot.

It SHALL name the first problem found, and SHALL leave any stored pack and
its state unchanged.

#### Scenario: Duplicate id

- **WHEN** a pack whose `daily` list contains `d007` twice is opened
- **THEN** the app says the id `d007` is used twice and the previously imported pack is still active

#### Scenario: Oversized picture

- **WHEN** a pack with one 3 MiB picture is opened
- **THEN** it is refused naming that picture, and nothing is stored

### Requirement: Re-importing a pack keeps everything already seen

The system SHALL treat a pack with the same `packId` as an update. It SHALL
show the difference (added and removed items per list, and pictures)
before applying it. On confirmation it SHALL keep, matched by item `id`,
every:

- revealed message and favourite;
- recorded day assignment;
- opened scroll and redeemed coupon;
- heart.

It SHALL ask for an explicit confirmation before replacing a pack with a
different `packId`.

#### Scenario: Forty new messages

- **WHEN** a pack with the same `packId` and 40 more daily messages is imported, after 12 messages had been revealed
- **THEN** the 12 revealed messages are still in the message box with their dates and favourites, and the 40 new ones join the unrevealed pool

#### Scenario: Another pack

- **WHEN** a pack with a different `packId` is opened
- **THEN** the app asks "Nahradit současný balíček?" and nothing changes until it is confirmed

### Requirement: The pack's texts and state are backed up, its pictures are not

The system SHALL include the pack's texts and its state in the backup
export, and SHALL restore them with the existing import. The state is the
revealed ids, favourites, day assignments, opened scrolls, the hearts
ledger and the import date. Pictures SHALL NOT be included. After a
restore without pictures, the theme SHALL use its built-in art and say
that re-importing the pack brings the pictures back.

#### Scenario: Restored on a new phone

- **WHEN** a backup taken with a pack, 50 revealed messages and 10 pictures is imported on a fresh install and the app is reopened
- **THEN** the partner theme is selectable, the message box shows the same 50 messages with their dates, built-in art is shown, and the love card says "Obrázky chybí – importuj balíček znovu"

#### Scenario: Pictures back

- **WHEN** the same pack is then re-imported
- **THEN** its 10 pictures appear in their slots and the 50 revealed messages are unchanged

### Requirement: Personal content and official artwork stay out of the repository

The repository SHALL contain only the pack schema, the engine, the tools
and a synthetic sample pack with original placeholder pictures. The build
SHALL NOT embed any pack. `tools/love-pack/build.mjs` SHALL build a pack
from a folder and SHALL check it with the same rules the app applies,
including the lore allow-list.

#### Scenario: Builder agrees with the app

- **WHEN** the builder is run on the synthetic sample with a duplicated id planted
- **THEN** it exits non-zero naming that id, and the app's decoder refuses the same file with the same reason

#### Scenario: Unknown lore tag

- **WHEN** a pack picture is tagged with a term not on the allow-list
- **THEN** the builder exits non-zero naming the picture and the term
