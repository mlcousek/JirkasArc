## ADDED Requirements

### Requirement: The partner theme is active only with a pack and when chosen

The system SHALL consider the partner theme active exactly when a valid
love pack is stored and the partner theme is the selected theme. Every
themed behaviour SHALL follow that one state: the greeting, the love card,
pictures, themed notification texts, the daily love notification, partner
achievements and rank names. It SHALL stop on the next render and the
next notification re-plan when the theme ends.

#### Scenario: Switching to Ocean

- **WHEN** the partner theme is active and the user selects Ocean
- **THEN** the Today greeting and love card disappear, level titles return to the standard tier names, and the next re-plan schedules standard notification texts and no love notification

#### Scenario: Pack removed

- **WHEN** the user removes the pack while the partner theme is selected
- **THEN** the app shows GF Teal and the partner theme is no longer in the picker

### Requirement: The partner theme mixes love pink and Naruto orange within the contrast rules

The partner theme SHALL use a pink accent and an orange second brand
colour, joined by a pink-to-orange gradient on the progress ring, the
level bar, the love card border and hero headers. It SHALL have light and
dark palettes that pass the same contrast guarantees as the other
non-Classic themes, and macro colours SHALL stay distinguishable from both
brand colours. Other themes SHALL render the gradient as their flat
accent.

#### Scenario: Contrast in both appearances

- **WHEN** the AppearanceKit tests evaluate the partner theme in light and dark appearance
- **THEN** text on accent measures at least 4.5:1 and the accent and the orange each measure at least 3:1 against cards in both

#### Scenario: Other themes unchanged

- **WHEN** Forest is active
- **THEN** the progress ring is drawn in Forest's flat accent, exactly as before this change

### Requirement: The theme is illustrated with original art, and pack pictures fill named slots

The partner theme SHALL ship original illustrations, an alternate app
icon, seven rank emblems and a badge for every partner achievement. All
SHALL be drawn for this app, with no official Naruto artwork, logo or
font. A pack picture SHALL appear only in the slots it names. Where several
pictures name a slot, the system SHALL rotate them daily, never showing the
same picture of the day two days in a row when another is available.
Built-in art SHALL fill every slot no picture names.

#### Scenario: Pack badge

- **WHEN** a pack picture names the slot `badge:p.genin` and "Genin" is unlocked
- **THEN** the achievement shows that picture inside its frame and rarity border

#### Scenario: No pictures

- **WHEN** a pack has no pictures
- **THEN** every slot shows the built-in illustration and no screen has an empty image area

#### Scenario: Picture of the day rotates

- **WHEN** three pictures name `pictureOfDay`
- **THEN** no two consecutive days show the same one

### Requirement: Logging and levelling up have themed motion, respecting Reduce Motion

While the partner theme is active, a confirmed log entry SHALL show a heart
burst with sakura petals and a spinning shuriken heart. It SHALL last at
most 700 ms, never cover the success state, and come with a two-tap
"heartbeat" haptic. A level-up SHALL show the new rank emblem. Under
Reduce Motion each SHALL be a static frame.

#### Scenario: Reduce Motion

- **WHEN** Reduce Motion is on and an entry is confirmed with the partner theme active
- **THEN** a static heart is shown, no burst animation plays, and the success check is visible

### Requirement: The partner theme's text is Czech whatever the app language

While the partner theme is active, the system SHALL show the theme's own
text in Czech, with correct Czech plural forms, also when the app language
is English: the greeting, the love card, rank names, partner achievement
titles, themed notification texts and empty states. Rows that appear
without the theme SHALL be available in English and Czech: import,
remove, and results.

#### Scenario: English phone

- **WHEN** the device language is English and the partner theme is active
- **THEN** the Today greeting reads "Dobré ráno, {nickname}" in Czech while the meal names stay English

#### Scenario: Plural forms

- **WHEN** the heart balance is 1, 3 and 7
- **THEN** it reads "1 srdíčko", "3 srdíčka" and "7 srdíček"

### Requirement: Today greets her and level titles become ninja ranks

While the partner theme is active, the Today header SHALL greet the pack's
nickname by time of day: "Dobré ráno" before 11:00, "Dobré odpoledne"
before 18:00, "Dobrý večer" after. Level tier titles SHALL show the ninja
rank names (Akademie, Genin, Chunin, Jonin, ANBU, Sannin, Kage, spread
across the 20 tiers), with their emblems, without changing any tier's
level range.

#### Scenario: Level title

- **WHEN** the user is at level 12 with the partner theme active
- **THEN** the level badge shows the ninja rank and emblem for that tier, with the same level and XP as under any other theme

### Requirement: Series references stay within the episodes already watched

Every theme text, built-in illustration and pack picture that references
the Naruto series SHALL carry lore tags. CI and the pack builder SHALL fail
when a tag is not on the owner-reviewed allow-list, which is limited to
what has appeared on screen up to Naruto Shippuden episode 30. CI SHALL
also fail when a theme text has an untagged capitalised word that is
neither a sentence start nor on the common-words list.

#### Scenario: Unknown tag

- **WHEN** a content entry is tagged with a term that is not on the allow-list
- **THEN** the localization CI job fails naming the entry and the term

#### Scenario: Forgotten tag

- **WHEN** an entry's text contains a mid-sentence capitalised name and the entry has no lore tags
- **THEN** the CI job fails naming the entry
