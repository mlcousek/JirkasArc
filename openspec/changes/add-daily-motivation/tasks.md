Branch `mlcousek/daily-motivation` on `main`. Nothing here was compiled locally
(no Swift toolchain); CI and the phone close the open boxes. Relative size S/M/L.

## 1. Domain (S)

- [x] 1.1 `FoodLogCore/Motivation/DailyMotivation.swift`: `slot`, `photoIndex`, `MotivationQuoteBook`, `MotivationPhotoFolder.photoURLs`.
- [x] 1.2 `Resources/motivation-quotes.json`: 365 original lines, en + cs, unattributed.
- [x] 1.3 `DailyMotivationTests`: slot bounds and leap day, photo wrap, 365 unique non-blank lines, folder listing skips non-images.

## 2. App (M)

- [x] 2.1 `GarminFood/Motivation/DailyMotivationCard.swift`: whole photo (`scaledToFit`), line, "Add photos" (`PhotosPicker`), refresh at a new day.
- [x] 2.2 Pinned at the top of `TodayView`; Settings toggle; `project.yml` file-sharing keys.
- [x] 2.3 Strings in `Localizable.xcstrings` (en keys + cs); `node tools/check-localizations.mjs` passes.

## 3. Love theme (S)

- [x] 3.1 On `mlcousek/love-photo-whole` (off `mlcousek/partner-love-theme`): the picture of the day uses `WholePhotoFrame` (fixed height, whole photo), no 180-pt crop.
- [x] 3.2 The love pack gets 21 more pictures (`pictureOfDay`), tagged only with allowlist terms; pictures that show unlisted characters were left out. Built with `tools/love-pack/build.mjs`.

## 4. Verify

- [ ] 4.1 CI green: FoodLogCore `swift test`, `xcodebuild` app, `localization`.
- [ ] 4.2 On the phone: add 3 photos, a tall one is whole; next day the line changes; the switch hides the card.
