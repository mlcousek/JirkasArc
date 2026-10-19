Every task ends with CI green: `swift test` for FoodLogCore, Gamification
and AppearanceKit, the design-token lint, the badge-art checks, the app and
widget `xcodebuild`, and the `localization` job. Every new `.swift` file
starts with a header comment saying why it exists and what depends on it.

**Nothing personal and no official artwork in the repository.** The only
pack here is the synthetic sample: nickname "Ninja", signature "Tvůj J.",
dates in 2030, placeholder texts, and original placeholder pictures. No
real name, date, message or Naruto picture goes into code, tests,
fixtures, docs, commit messages or CI artifacts.

No new target, entitlement or background mode. Branch
`mlcousek/partner-love-theme` on `main`. Relative size: S / M / L.

Nothing here is compiled locally (no Swift toolchain). A box is ticked
when the code was written and read back against its call sites and tests.
Section 9 stays open until CI and her phone have said so.

## 1. Design and owner decisions (S)

- [x] 1.1 `proposal.md`, `design.md`, the spec deltas and this file; `openspec validate add-partner-love-theme --strict`.
- [x] 1.2 Owner decisions 2026-10-19: one message a day, 08:00–13:00 every day, no special dates, theme-only, pink + orange, stay free.
- [ ] 1.3 **Owner reviews `tools/love-pack/lore-allowlist.json`** (design D11, boundary Shippuden 30). Can't be ticked by code.
- [ ] 1.4 Owner answers design Open Questions 1–3 (starter messages, extras, home-screen name).

## 2. The pack, pure, and its tools (M)

- [x] 2.1 FoodLogCore `Love/LovePack.swift`: `love-pack` v1 `Codable`; validation naming the first problem (40 MiB before parsing, required fields, unique ids, 600-character texts, 2 000 items, at most 80 pictures, PNG/JPEG by magic bytes, ≤ 2 MiB, ≤ 4096 px, known slots).
- [x] 2.2 `Love/LovePackDiff.swift`: added and removed per list and pictures; same pack vs another pack.
- [x] 2.3 `Love/LoveState.swift` (`FoodLogCore/Love/love-state.json`): revealed ids with dates, favourites, day → id assignments, opened scrolls, hearts ledger, import date; tolerant decoding.
- [x] 2.4 `StoreCatalog` (`foodlog.love`): `love-pack.json` and `love-state.json` in backups; `Love/Images/` (not JSON) excluded from backups and snapshots; check `BackupSecretPolicy` does not drop the texts.
- [x] 2.5 Synthetic sample (`tools/love-pack/sample/`, built `sample.arclove`) and the store fixtures `love-pack.json`/`love-state.json`; tests: valid, each refusal, re-import keeps state, another pack, backup round trip without pictures.
- [x] 2.6 `tools/love-pack/build.mjs` (folder to `.arclove`, the same rules plus lore tags, size report) and `lore-allowlist.json`; run in CI on the sample and on a planted-duplicate copy.

## 3. The daily message, pure (M)

- [x] 3.1 `Love/DailyLoveMessage.swift`: day index, seeded permutation over unrevealed ids, favourites-first refill, recorded assignments never re-drawn.
- [x] 3.2 `Love/LoveMinute.swift`: SHA-256(seed, date) to 08:00–12:59; 10-minute clash shift before 13:00; DST wall-clock.
- [x] 3.3 `Love/LoveReveal.swift`: revealed at the minute or on open; nothing shown before.
- [x] 3.4 `Love/PictureRotation.swift`: per-slot daily rotation, no repeat on consecutive days.
- [x] 3.5 `CzechPlural` (0, 1, 2–4, 5+) and tests.
- [x] 3.6 Tests: 30 days give 30 distinct messages; assignment survives a re-import; exhaustion; the 1 000-date window including weekends; the clash; DST days 2030-03-31 and 2030-10-27; reveal before and after the minute.

## 4. Notifications (M)

- [x] 4.1 The text seam: `NotificationPlanning.themed(_:today:texts:)` (and its fasting overload) applied after planning; `texts: nil` returns the plan unchanged (existing tests unchanged). `Love/LoveNotifications.swift`.
- [x] 4.2 The love kind (`love.daily.<date>`, `LoveNotificationPlanning.plan`) for days 0–6, its minute kept away from the CONFIGURED reminder times (`clashMinutes`) so logging a meal never moves it, and `NotificationBudget.foodWindowDays` (the 60-request cap shrinks the food window); tests with every kind on.
- [x] 4.3 `ThemedNotificationTexts`: variants per kind, chosen by `stableHash(seed, day, kind)` (stable per day; repeating fasting requests keep one), `{nickname}`/`{signature}` filled, a `nil` body keeps the standard body (supplements). The Czech wording itself is task 5.3.
- [x] 4.4 App: `NotificationScheduler.syncLoveNotifications` (calendar trigger at the wall-clock minute, picture ≤ 1 MiB copied and attached, the `love.` namespace diffed like every cycle), themed food and fasting texts, the budget computed from what is already pending; `AppEnvironment.syncNotifications` runs love first and food last. A tap goes through the existing delegate (`onLoveNotificationOpened`, parked until launch finishes) instead of a URL: it reveals the day and opens Today.

## 5. Theme (M)

- [x] 5.1 AppearanceKit `UnlockedTheme.partner` (`UnlockedThemes.swift`): pink/orange palettes checked against D5 (no new token: the existing `accentSecondary` and header-gradient roles carry the orange and the pink→orange gradient), `over` moved to violet; `AppearanceEnvironment.unlockedThemeIDs` (without it a stored partner theme resolves as GF Teal); `ThemeCatalog.available(unlocked:)` for the picker; `ThemeShareCode.isShareable` and `.unshareableTheme` (the app shows "This theme can't be shared." and words the failure, en + cs). `PartnerThemeTests`.
- [x] 5.2 `PartnerThemeModel.isActive` (PartnerTheme/PartnerThemeModel.swift): pack stored AND partner theme selected; the stored `partner.packInstalled` bit unlocks the theme at launch (no flash), `reload()` corrects it.
- [x] 5.3 `PartnerTheme/Resources/partner-theme.cs.json` (decoded by FoodLogCore `PartnerThemeContent`, checked by `PartnerThemeContentTests`) and the `PartnerText` table (placeholders, lore tags): greeting, rank names over the 20 tiers, notification variants, achievement texts, empty states.
- [x] 5.4 The lore lint as its own script, `tools/love-pack/lint-theme-content.mjs` (tags on the allow-list, untagged mid-sentence capitals), with tests in `tools/love-pack/test.mjs`, in the localization job. No scanner exemption needed: the table is not SwiftUI literals, and `Text(verbatim:)` is already accepted.
- [x] 5.5 `Info.plist` (project.yml): exported UTI `com.mlcousek.garminfood.arclove` and its document type, not opened in place; `AppRouter.handle(url:)` sends the file to the import sheet.

## 6. Art (L)

- [ ] 6.1 Style sheet in `ios/PartnerArt/README.md` (D4: outline colour, palette, proportions, sizes) and a contact-sheet page built by `tools/docs/` for review in the browser.
- [ ] 6.2 App icon: a pink→orange heart with a spiral cut-out and shuriken, @2x/@3x, as an alternate icon.
- [ ] 6.3 Illustrations: chibi fox with heart, two chibi ninjas with heart, ramen with heart fish-cake, scroll (closed and open), toad with heart, sakura branch with kunai, shuriken heart, night sky.
- [ ] 6.4 Seven rank emblems.
- [ ] 6.5 Badges for every partner achievement (D9), in the existing frames and rarity borders.
- [ ] 6.6 Every piece passes `lint-badge-svg.mjs`, is in `build-badge-assets.mjs --check`, carries lore tags, and is listed in a catalog test.
- [ ] 6.7 The art resolver: slot to pack picture (rotation) or built-in art; badge masking into the frame.

## 7. Screens (L)

- [x] 7.1 Settings > Appearance > Love pack (`LovePackSection`): "Import love pack…" (file importer), `LovePackImportSheet` (the diff, "Replace the current love pack?", every problem worded), remove with confirmation, the missing-pictures note (en + cs); the theme in the gallery once unlocked.
- [x] 7.2 Today: `LoveCardView` -- the greeting by time of day, the love card (pink→orange gradient border, the message or "dorazí dopoledne" and nothing of its text before the minute, the favourite heart, the signature, the picture of the day, the optional countdown, the way into the message box), revealing by itself when the minute comes while Today is open. Level titles become ninja ranks (`PartnerThemeModel.levelTitle`: the level card, the level detail, the level-up moment). **Deviation:** pinned at the top of Today rather than a layout card id (a new id would appear in every layout editor); the evening sky waits for the art (section 6).
- [ ] 7.2b The love card as a movable layout card id, shown in the layout editor only while the theme is on.
- [x] 7.3 `MessageBoxView` ("Krabička vzkazů"): revealed messages newest first with Czech dates, the favourites filter, scrolled to a tapped notification's day. Header art waits for section 6.
- [x] 7.4 `OpenWhenView` ("Otevři, až…", only with pack content, linked from the love card): sealed and opened states, opened for good, unrolling reveal (Reduce Motion: fade).
- [x] 7.5 `HeartBurstOverlay` on the root: after every confirmed log (`AppEnvironment.logConfirmed`), a heart with seven sakura petals and a spinning shuriken heart (both shapes drawn in code), 700 ms, never taking a touch; `Haptics.heartbeat()` (two soft taps); Reduce Motion: one still heart that fades; decorative, hidden from VoiceOver. The rank emblem on level-up waits for the art (6.4).

## 8. Partner achievements and hearts (M)

- [ ] 8.1 Gamification `PartnerAchievementSet` (design D9 table): evaluated only while active, counted from the import date, secret ones through the reveal moment, scroll and coupon ones only with pack content.
- [ ] 8.2 Hearts ledger (earned, spent; derived balance) and coupons (redeem, "Uplatněné", the stamped scroll).
- [ ] 8.3 Tests: hidden on another theme; no burst on day one; XP unchanged (`XPBudgetTests` untouched and green); not enough hearts; redemption.

## 9. Ship to her phone (S)

- [ ] 9.1 `docs/partner-phone-setup.md`: AltStore or SideStore under her Apple ID, the 7-day refresh, standalone onboarding, Czech, notifications on, pack import, the export-backup reminder.
- [ ] 9.2 CI green on the PR.
- [ ] 9.3 Sideloaded on her phone: pack imported, theme on, the first love notification observed between 08:00 and 13:00, still notified after 2 days with the app closed. Record dates and minutes, without the text.
