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

- [ ] 4.1 `NotificationTextProvider` seam in `NotificationPlanning`; the default provider returns today's texts (existing tests unchanged).
- [ ] 4.2 The love kind (`love.daily.<date>`) for days 0–6, its priority and the 60-request cap; a test with every kind on.
- [ ] 4.3 Partner text provider: 3–7 variants per kind from the content table, stable per day.
- [ ] 4.4 App: `NotificationScheduler` feeds `PartnerMode`; picture attachment ≤ 1 MiB; deep link `garminfood://love/day/<date>` (`GarminFoodDeepLink`).

## 5. Theme (M)

- [ ] 5.1 AppearanceKit `UnlockedTheme.partner`: pink/orange palettes (D3), the `brandGradient` token (flat accent for every other theme), `ContrastPolicy` tests light and dark, ΔE of macros vs both brand colours; picker visibility; share-code refusal; fallback to GF Teal.
- [ ] 5.2 `PartnerMode.isActive`: one place, observed by Today, the scheduler, Gamification and the art resolver.
- [ ] 5.3 `PartnerTheme/Resources/partner-theme.cs.json` and the `PartnerText` table (placeholders, lore tags): greeting, rank names over the 20 tiers, notification variants, achievement texts, empty states.
- [ ] 5.4 `check-localizations.mjs`: the `PartnerTheme/` `Text(verbatim:)` exemption; the lore lint (tags on the allow-list, untagged capitalised words); tests for the lint.
- [ ] 5.5 `Info.plist`: exported UTI and document type for `.arclove` (no entitlement).

## 6. Art (L)

- [ ] 6.1 Style sheet in `ios/PartnerArt/README.md` (D4: outline colour, palette, proportions, sizes) and a contact-sheet page built by `tools/docs/` for review in the browser.
- [ ] 6.2 App icon: a pink→orange heart with a spiral cut-out and shuriken, @2x/@3x, as an alternate icon.
- [ ] 6.3 Illustrations: chibi fox with heart, two chibi ninjas with heart, ramen with heart fish-cake, scroll (closed and open), toad with heart, sakura branch with kunai, shuriken heart, night sky.
- [ ] 6.4 Seven rank emblems.
- [ ] 6.5 Badges for every partner achievement (D9), in the existing frames and rarity borders.
- [ ] 6.6 Every piece passes `lint-badge-svg.mjs`, is in `build-badge-assets.mjs --check`, carries lore tags, and is listed in a catalog test.
- [ ] 6.7 The art resolver: slot to pack picture (rotation) or built-in art; badge masking into the frame.

## 7. Screens (L)

- [ ] 7.1 Settings > Appearance: "Import love pack…" (file importer), the import preview with the diff, remove with confirmation (en + cs).
- [ ] 7.2 Today: the greeting header (with the evening sky); the love card (gradient border, message or "dorazí dopoledne", picture of the day, optional countdown) as a layout card id.
- [ ] 7.3 Message box: revealed list, favourites filter, deep-link scroll target, header art.
- [ ] 7.4 "Otevři, až…" scrolls (only with pack content): sealed and opened states, unrolling animation (Reduce Motion: fade).
- [ ] 7.5 Heart burst with petals and shuriken on confirm, `heartbeat` haptic, the rank emblem on level-up; Reduce Motion static frames; VoiceOver labels.

## 8. Partner achievements and hearts (M)

- [ ] 8.1 Gamification `PartnerAchievementSet` (design D9 table): evaluated only while active, counted from the import date, secret ones through the reveal moment, scroll and coupon ones only with pack content.
- [ ] 8.2 Hearts ledger (earned, spent; derived balance) and coupons (redeem, "Uplatněné", the stamped scroll).
- [ ] 8.3 Tests: hidden on another theme; no burst on day one; XP unchanged (`XPBudgetTests` untouched and green); not enough hearts; redemption.

## 9. Ship to her phone (S)

- [ ] 9.1 `docs/partner-phone-setup.md`: AltStore or SideStore under her Apple ID, the 7-day refresh, standalone onboarding, Czech, notifications on, pack import, the export-backup reminder.
- [ ] 9.2 CI green on the PR.
- [ ] 9.3 Sideloaded on her phone: pack imported, theme on, the first love notification observed between 08:00 and 13:00, still notified after 2 days with the app closed. Record dates and minutes, without the text.
