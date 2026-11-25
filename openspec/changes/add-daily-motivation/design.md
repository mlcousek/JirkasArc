## D1. Which line, which photo (pure, in FoodLogCore)

`DailyMotivation.slot(for:calendar:)` = day of the year, 1...365 (Dec 31 of a
leap year reuses 365), minus one. The line is `quotes[slot]`; the photo is
`photos[slot % photos.count]` over the photo files sorted by name. Both are a
function of the local calendar day alone: no random state, no store, the
same on every launch, and tomorrow's pick is always a different line (and a
different photo whenever there are two or more).

## D2. Where the photos come from

Only from the phone: `Documents/Motivation/`. Documents is exposed in the
Files app (`UIFileSharingEnabled`, `LSSupportsOpeningDocumentsInPlace`), so
the owner can drop a folder of photos in from a computer or iCloud Drive, and
the card's "Add photos" runs `PhotosPicker` (multi-select) and copies each
pick into that folder under a UUID name. Why not bundle them: the repository
is public. Why not a JSON store: the files are the data; a store would only
duplicate it. A file that does not decode is skipped, never fatal.

## D3. Shown whole

`DesignSystem/WholePhotoFrame`: a frame as wide as the card and ONE fixed
height (380 pt), the photo fitted (`scaledToFit`) and centred in it, the
left-over space filled by a blurred, dimmed copy of the same photo. A tall
wallpaper and a wide meme take the same box, so the card never changes height
from day to day and nothing is cropped. Decoded by ImageIO at no more than
1600 px on the long side off the main thread. The love card uses the same view
(its 180-pt `scaledToFill` crop is gone); the file is byte-identical on both
branches so they merge cleanly.

## D4. The lines

`motivation-quotes.json`: `[{"en": "...", "cs": "..."}]`, exactly 365 (a test
pins the count and that no two lines are equal and none is blank). The
language follows the app's language (`cs` -> Czech, else English). Themes are
mixed so a week reads varied: discipline, suffering and calluses, running and
ultras, the gym, programming and craft, rest and recovery, consistency.

## D5. Off switch

`@AppStorage("dailyMotivationEnabled")`, default true, in Settings →
Preferences. Off hides the whole card; the files stay.

## Non-goals

Per-day picking of a photo, captions, sharing a photo, a notification with
the line (a later change can reuse `DailyMotivation`), syncing photos.
