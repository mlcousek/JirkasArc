# food-catalog Specification

## Purpose
Provide a fast way to find a food to log — by search, barcode, or a locally-ranked quick-pick shelf — backed by Garmin's own food database so that anything found is guaranteed loggable back to Garmin, plus a custom-food path for items that database does not carry.

## Requirements

### Requirement: Food search is backed by Garmin's own database

The system SHALL search for foods via Garmin's `food/search` route (`GET /nutrition-service/food/search?searchExpression=<term>`, confirmed reachable 2026-09-14) rather than maintaining an independent food database, so that any food found is guaranteed to be a food Garmin recognises for logging.

#### Scenario: Searching for a common food

- **WHEN** the user searches for a food by name
- **THEN** results are retrieved from Garmin's food-search route
- **AND** each result includes its available serving options

#### Scenario: Searching in Czech

- **WHEN** the user searches using a Czech-language term
- **THEN** relevant results are returned, because Garmin's underlying database has non-US coverage

### Requirement: A quick-pick shelf is ranked from local usage, not from a fresh search

The system SHALL maintain a local record of previously logged foods and servings, and SHALL rank a "quick pick" list from that record by a combination of recency and frequency, so that the most likely food is available without typing or waiting on a search.

#### Scenario: A frequently logged food is picked again

- **WHEN** the user has logged the same food and serving multiple times recently
- **THEN** it appears near the top of the quick-pick list without a search being performed

#### Scenario: No usage history exists yet

- **WHEN** no food has ever been logged
- **THEN** the quick-pick list is empty rather than populated with unranked guesses

### Requirement: A food's serving choice is remembered as a default

Once a serving has been selected for a given food, the system SHALL remember that selection and pre-select it the next time the same food is chosen, while still allowing the user to change it.

#### Scenario: Re-logging a previously served food

- **WHEN** the user selects a food they have logged before
- **THEN** the previously chosen serving is pre-selected

#### Scenario: Changing the remembered serving

- **WHEN** the user selects a different serving than the remembered default
- **THEN** the new selection becomes the remembered default for that food going forward

### Requirement: Barcode scanning resolves a scanned product to a Garmin food

The system SHALL scan EAN-13, EAN-8, UPC-E, Code 128, ITF-14 and GS1 DataBar barcodes and attempt to resolve the scanned code to a Garmin food. Because UPC-A barcodes are reported by the scanning framework as EAN-13 with a leading zero, the system SHALL retry resolution with the leading zero stripped before treating the scan as unresolved.

#### Scenario: A UPC-A product barcode is scanned

- **WHEN** a UPC-A barcode is scanned and reported as a 13-digit code with a leading zero
- **THEN** the system also attempts resolution using the 12-digit code without the leading zero

#### Scenario: A scanned barcode cannot be resolved to any food

- **WHEN** no food can be found for a scanned barcode, with or without the leading zero
- **THEN** the user is offered custom-food creation rather than a dead end

### Requirement: Custom foods use the same shape a logged entry requires

The system SHALL allow creating a custom food with the same fields the food-log write contract requires, so that a custom food can be logged through the same flow as a Garmin catalog food.

#### Scenario: Creating a custom food

- **WHEN** the user creates a custom food with a name, serving unit and macro values
- **THEN** it can be selected and logged exactly as a searched food can

#### Scenario: Custom food creation is not possible via the Garmin API

- **WHEN** the write contract does not support creating a new food server-side
- **THEN** a custom food logs as the closest matching existing Garmin food with an adjusted quantity
- **AND** the discrepancy between the custom food and the food actually recorded in Garmin is shown to the user

### Requirement: A barcode can be resolved from manual digit entry, not only a camera scan

The system SHALL offer a manual entry path for a barcode when scanning it
with the camera is not possible or not working, and SHALL resolve a
manually entered code through the same resolution logic (including UPC-A/
EAN-13 leading-zero normalisation) used for a camera-scanned code, so the
outcome for the user is identical regardless of entry method.

#### Scenario: Manually entering a barcode that resolves to a Garmin food

- **WHEN** the user types a barcode's digits instead of scanning it
- **THEN** the system attempts resolution exactly as it would for a scanned
  code of the same value
- **AND** a resolved food is presented the same way a camera-scanned result
  would be

#### Scenario: Manually entering an implausible value

- **WHEN** the user types a value that is not shaped like a real barcode
  (too short, too long, or containing non-digit characters)
- **THEN** the system does not attempt a lookup for it

### Requirement: A food can be marked as a local favorite for fast re-access

The system SHALL let the user mark or unmark any food shown in the primary
logging flow (search results, the quick-pick shelf, custom foods) as a
favorite, storing that choice locally, so that a food useful for future
logging can be found again without a search -- independent of whether
Garmin's own account state agrees, and without waiting on any network call.

#### Scenario: Marking a search result as a favorite

- **WHEN** the user taps the favorite toggle on a food shown in search
  results
- **THEN** the food is marked favorite instantly, with no network wait
- **AND** it subsequently appears in the Favorites shelf

#### Scenario: Unmarking a favorite

- **WHEN** the user taps the favorite toggle on a food that is already
  favorited
- **THEN** the food is no longer marked favorite
- **AND** it no longer appears in the Favorites shelf

#### Scenario: Favoriting is not offered while picking a food for another screen

- **WHEN** the catalog is being used to pick a backing food for a custom
  food, or an ingredient for a meal preset
- **THEN** no favorite toggle is shown on any row

### Requirement: A Favorites shelf surfaces favorited foods for fast re-logging

The system SHALL show a horizontally-scrolling Favorites shelf in the
primary logging flow whenever at least one food is favorited, at the same
prominence as the existing quick-pick shelf, so that favoriting is
immediately useful rather than a bookmark that is never revisited.

#### Scenario: No favorites yet

- **WHEN** the user has never favorited a food
- **THEN** the Favorites shelf is not shown at all

#### Scenario: Selecting a favorited food

- **WHEN** the user taps a card in the Favorites shelf
- **THEN** the same food-selection flow used for a search result begins
  (the remembered serving is pre-selected if one exists, otherwise a
  serving picker is shown)

### Requirement: Favoriting has no dependency on a Garmin write route

The system SHALL implement favoriting entirely as local state, with no
network call of any kind, because no third-party Garmin Connect client
this project has evidence-checked has ever implemented a favorite-foods
method, and this project's own convention prohibits guessing at an
undocumented write contract.

#### Scenario: Favoriting while offline

- **WHEN** the device has no network connectivity
- **THEN** marking or unmarking a favorite still succeeds immediately

### Requirement: Picking an ingredient searches every food source

The system SHALL offer the same food sources when picking a meal-preset
ingredient as when logging a food: Garmin search results, Czech Open Food
Facts results, and the user's custom foods matched by name.

#### Scenario: Czech product found while building a meal

- **WHEN** the user adds an ingredient to a meal preset and searches for a Czech product that only Open Food Facts has
- **THEN** the Open Food Facts section is shown in the picker
- **AND** choosing that product, after the Garmin match is confirmed, adds the matched food to the meal instead of logging it

#### Scenario: Custom food found by typing while building a meal

- **WHEN** the user types part of a custom food's name in the ingredient picker
- **THEN** that custom food is listed and can be added to the meal

### Requirement: A tap in picker mode never logs a food

The system SHALL return the tapped food to the calling screen, and SHALL NOT
log it, whenever the catalog is open to pick an ingredient or a backing food.
This applies to quick-pick cards, favorites, custom foods and search results.

#### Scenario: Quick pick tapped while adding an ingredient

- **WHEN** the catalog is open to add a meal-preset ingredient and the user taps a Quick pick card
- **THEN** the food is added to the meal preset with that card's serving and quantity
- **AND** no food log entry is created

### Requirement: The Log Food screen offers swipeable shelves in a fixed order

When the search field is empty, the system SHALL show horizontal card shelves
in this order: Quick pick, Favorites, Usual for <meal>, Meals, Recent. The
system SHALL hide any shelf that has no items.

#### Scenario: Meals shown as cards
- **WHEN** the user has two meal presets and opens Log Food
- **THEN** both presets appear as cards in the Meals shelf, after Usual for <meal>
- **AND** tapping a card opens the preset's confirm screen

#### Scenario: Empty shelf hidden
- **WHEN** the user has no favorites
- **THEN** no Favorites shelf is shown and the next shelf moves up

### Requirement: A per-meal shelf surfaces the foods usually eaten at that meal

The system SHALL show a "Usual for <meal>" shelf. It lists the foods most
often logged for the meal currently being logged, ranked by frequency with a
recency decay. The shelf SHALL only appear once that meal has at least 3
logged events.

#### Scenario: Breakfast staples at breakfast
- **WHEN** the user opens Log Food from the Breakfast card, and oatmeal was logged at breakfast 8 times and at dinner 0 times
- **THEN** the shelf is titled "Usual for breakfast" and oatmeal appears in it

#### Scenario: Dinner shelf differs
- **WHEN** the user opens Log Food from the Dinner card
- **THEN** oatmeal does not appear in "Usual for dinner" unless it was logged at dinner

### Requirement: A Recent shelf lists the last foods logged

The system SHALL show a Recent shelf with the last 10 distinct foods logged,
newest first.

#### Scenario: Just-logged food is first
- **WHEN** the user logs a banana and reopens Log Food
- **THEN** the banana is the first card in Recent

### Requirement: Search returns one ranked list across all sources

The system SHALL return search results as a single list ranked by relevance.
The list covers the user's own foods (custom foods, favorites, previously
logged foods), Garmin's database (`GET /nutrition-service/food/search`,
confirmed 2026-09-14), and Czech Open Food Facts. Each result SHALL show a
small source badge. Duplicates of the same product across sources SHALL
appear once.

#### Scenario: Own custom food found by typing

- **WHEN** the user has a custom food "Domácí tvaroh" and types "tvaroh"
- **THEN** "Domácí tvaroh" appears in the results, marked as the user's own food

#### Scenario: Same product from two sources

- **WHEN** Garmin and Open Food Facts both return "Madeta Jihočeský tvaroh" with calories within 5% per 100 g
- **THEN** it appears once, as the directly loggable Garmin item

### Requirement: Matching tolerates Czech inflection, word order, diacritics and typos

The system SHALL match a query against food names regardless of:

- diacritics and letter case;
- word order;
- common Czech inflected forms;
- a single-character typo in words of four or more letters.

#### Scenario: Inflection

- **WHEN** the user searches "rohlíky"
- **THEN** foods named "Rohlík" are among the top results

#### Scenario: Word order and no diacritics

- **WHEN** the user searches "tvaroh mekky"
- **THEN** "Měkký tvaroh" is among the top 3 results

#### Scenario: Typo

- **WHEN** the user searches "banan" or "chlba"
- **THEN** "Banán" or "Chléb" respectively is among the top 3 results

#### Scenario: Unrelated garbage is not shown

- **WHEN** no word of a candidate matches any query word at any tier
- **THEN** that candidate is not shown

### Requirement: Foods the user eats often rank higher

The system SHALL boost results by how often and how recently the user has
logged them, and by favorite status, so that among comparable matches the
user's usual food ranks first.

#### Scenario: Usual yogurt first

- **WHEN** two yogurts match "jogurt" equally and the user logged one of them 10 times last month
- **THEN** that yogurt ranks above the other

### Requirement: Results appear instantly and update without jumping

The system SHALL show matching local foods on the first keystroke without
waiting on the network. The system SHALL merge remote results as they arrive
without reordering rows already shown. It SHALL keep previous results visible
while loading, and SHALL never report a cancelled request as an error.

#### Scenario: Offline typing

- **WHEN** the device is offline and the user types the name of a food they logged before
- **THEN** that food is shown immediately, with a note that online databases are unavailable

#### Scenario: Fast typing

- **WHEN** the user types quickly, cancelling in-flight requests
- **THEN** no error message flashes

### Requirement: A custom food never sends Garmin an out-of-range amount

The system SHALL log a custom food backed by a Garmin food only when the amount sent to Garmin, the logged amount times the custom food's quantity multiplier, is finite, greater than zero and at most the maximum any logged amount may be. Otherwise it SHALL queue nothing and SHALL tell the user why before they confirm. This applies whatever the stored multiplier is, including one never checked by the editor.

#### Scenario: Multiplier times amount above the maximum
- **WHEN** a custom food with a multiplier of 100 is confirmed at 200 servings
- **THEN** nothing is queued, "Log it" is disabled, and the screen says the amount recorded in Garmin is out of range

#### Scenario: Stored multiplier of zero
- **WHEN** a custom food whose stored multiplier is 0 is logged from any entry point
- **THEN** nothing is queued for Garmin

#### Scenario: Meal preset with an out-of-range custom ingredient
- **WHEN** a meal preset's portions make one custom ingredient's amount in Garmin exceed the maximum
- **THEN** no ingredient of the preset is queued
