## Why

The owner's partner theme (branch `mlcousek/partner-love-theme`) opens Today
with a picture of the day and a daily message. The owner wants the same
morning lift in the normal app: one photo and one motivational line a day
(hard work, running and ultras, the gym, programming), 365 lines so none
repeats within a year, and the photo always shown whole -- the love theme's
card crops it to a 180-pt strip.

## What Changes

- A **daily motivation card** pinned at the top of Today (not a layout card
  id: a new id would appear in everyone's layout editor, the same call the
  love card made): today's photo shown whole, and today's line under it.
- **365 original lines**, English and Czech, bundled in FoodLogCore. They
  are NOT attributed to anyone: the lines are written in the spirit of David
  Goggins, ultrarunning, gym and craft, but a quote is never put in a real
  person's mouth.
- **The photos are the owner's, not the repository's.** The repository is
  public and the pictures are personal or someone else's, so they live on
  the phone only: `Documents/Motivation/` (visible in the Files app) and an
  "Add photos" button on the card (the system photo picker copies the pick
  there; no permission prompt). Without photos the card shows the line alone.
- A Settings switch ("Daily photo and quote"), on by default.
- **Love theme fix** (separate branch off the love branch): its picture is
  shown whole (`scaledToFit`, no fixed 180-pt crop frame).

## Impact

- FoodLogCore: `Motivation/DailyMotivation.swift` (pure: which line and
  which photo for a day, the quote book, the photo list), a bundled
  `motivation-quotes.json`, tests.
- App: `GarminFood/Motivation/DailyMotivationCard.swift`, one line in
  `TodayView`, one toggle in `SettingsView`, strings in the catalog,
  Info.plist file-sharing keys in `project.yml`.
- No Garmin route, no vault write, no new store file (the photos are plain
  image files, not a JSON store; the switch is a UserDefaults flag).
- Photos are not part of the weekly vault backup (size cap 3 MiB, and they
  are the owner's files already).
