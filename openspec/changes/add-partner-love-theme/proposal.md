## Why

The app is going onto a second iPhone: the owner's fiancée's ("the
partner"). She will run it standalone ("Just on this phone": no Garmin, no
vault, which `add-standalone-mode` already provides), in Czech, and she
should feel that this copy was made for her. The owner wants:

- a theme of her own: love-pink mixed with Naruto orange, hearts and a
  ninja world, Naruto pictures and badges, cute illustrations, in Czech
  only;
- one kind message from him every day, a different one each day, arriving
  at a random time between 8:00 and 13:00;
- every notification the app sends to sound different while the theme is
  on;
- achievements that exist only in that theme;
- no spoilers: they are watching Naruto Shippuden and are at episode 30.

Two facts shape everything below. The repository is **public**, and its
rule is "nothing personal in the repository". Everything in it is
published, and it has to stay public for the free macOS CI minutes. So
the love messages, her nickname and the official Naruto pictures she will
see cannot be in it. They are for her phone only (owner, 2026-10-19).
And a free Personal Team has no App Groups, so the widget cannot read
anything the app stores. The owner keeps development free (decision
2026-10-19).

## What Changes

- **A private love pack.** Everything personal and every official picture (her
  nickname, his signature, the daily messages, the optional extras, and
  any official Naruto pictures) lives in one file, `*.arclove`. The owner
  builds it outside the repository with `tools/love-pack/build.mjs` and
  gives it to her phone via AirDrop or Files. The repository holds only the
  schema, the engine, the tools and a synthetic sample pack. Importing a
  pack unlocks the theme. With no pack, nothing in this change shows. A
  pack can be re-imported to add messages or pictures, and nothing already
  revealed is lost.
- **The "Srdce ninji" theme.** A pack-unlocked theme mixing **sakura pink
  (love)** and **Naruto orange**: a pink→orange gradient on the progress
  ring, the hero cards and the level bar, pink as the accent and orange as
  the second brand colour. It has light and dark palettes, contrast-fitted
  like every theme, and its own app icon.
- **Original art in the repository, official pictures from the pack.**
  The repository gets a set of original, Naruto-*inspired* SVG
  illustrations, all drawn for this app and in the existing badge-art
  pipeline:
  - a chibi ninja fox with a heart
  - two chibi ninjas sharing a heart
  - a ramen bowl with a heart-shaped fish-cake swirl
  - a love-letter scroll with a heart seal
  - a toad holding a heart
  - a sakura branch with a kunai
  - seven rank emblems
  - a badge for every theme achievement

  The pack may add official Naruto pictures into named slots (love card,
  message box header, empty states, any achievement's badge, a picture of
  the day). Built-in art fills any slot the pack leaves empty.
- **Ninja feel throughout.** A greeting on Today ("Dobré ráno,
  <přezdívka> ❤️"). Ninja ranks (Akademie → Genin → Chunin → Jonin → ANBU
  → Sannin → Kage) replace the level tier titles. A heart burst with
  sakura petals and a spinning shuriken plays when she logs (static under
  Reduce Motion), with a heartbeat haptic. Czech only: the theme's text is
  not translated and shows in Czech whatever the app language is.
- **One love message a day.** Each calendar day gets exactly one message
  from the pack. Each day's is different, and none repeats until the pack
  runs out. There are no special-date messages. It arrives as a local
  notification at a random minute between 08:00 and 13:00, every day of
  the week. The minute is fixed for that day, so re-planning never moves
  it, and it is kept pending for the coming days, so it fires with the
  app closed. Before its minute, Today says "Dnešní vzkaz dorazí dopoledne
  💌". After it, the message is on Today and in the **Krabička vzkazů**
  (message box): every past day's message, with a heart to keep
  favourites. Future messages can never be seen.
- **Themed notifications.** While the theme is on, every notification the
  app writes (meal, streak, daily challenges, fasting, habits, supplement
  titles) uses Czech ninja-love texts, with several variants per kind. The
  rules for when a notification fires do not change.
- **Theme-only achievements: "Svitky srdce".** About 18 achievements,
  visible and evaluated only while the theme is on, counted from the day
  the pack was imported. Some are secret. They pay **srdíčka** (hearts), a
  theme-only currency, and never XP, so the XP economy is untouched.
- **Optional extras, shown only when the pack has them.** **Love coupons**
  bought with hearts ("Večeře podle tvého výběru – 40 ❤️").
  **"Otevři, až…"** sealed scrolls (až jsi smutná, až mi chybíš), each
  opened once. A **countdown** to one date of his choice. These are not
  daily: the one-message-a-day rule holds.
- **No-spoiler rule.** Every Naruto reference, in text and in pictures, is
  tagged with the lore terms it uses. A CI lint (and the pack validator)
  fails when a tag is not on an owner-reviewed allow-list of things
  already seen by Shippuden episode 30. It is an allow-list, not a
  deny-list: a list of things to avoid would itself be a spoiler.
- **Setting up her phone**: `docs/partner-phone-setup.md` covers AltStore or
  SideStore under her own Apple ID, standalone onboarding, importing the
  pack and switching notifications on.

## Capabilities

### New Capabilities

- `love-pack`: the private content file with its pictures, how it is
  built, imported, validated and re-imported, and what unlocks with it.
- `partner-theme`: the theme, its palette and art, picture slots, the
  Czech-only content table, the greeting, rank names, motion and haptics,
  and the spoiler allow-list.
- `love-messages`: the daily message, its choice and random time, reveal,
  the message box, "open when" scrolls and the countdown.
- `partner-achievements`: the theme-only achievements, hearts and coupons.

### Modified Capabilities

- `reminder-notifications`: themed texts while the theme is on, and the
  daily love message in the pending-request budget.
- `app-theming`: a pack-unlocked theme beside the 13 built-in ones.

## Non-goals

- Active calories from Apple Health: owned by
  `add-health-active-calories`.
- Pairing the two phones, the couple streak, pokes and notes, and coupon
  redemption reaching his phone: owned by `add-couple-link-and-streak`.
- Special-date messages (owner decision 2026-10-19: one kind message a
  day, nothing else).
- A widget showing the daily message: not possible on the free tier (the
  widget cannot read the app's container).
- Official Naruto pictures in the repository or in CI artifacts (they are
  public). They reach her phone through the pack.
- Translating the theme into English.
- Any change to XP, levels, streak rules or the existing achievements.
- Stopping her from changing the device clock to peek. A revealed message
  stays revealed. Nothing more is attempted.

## Impact

- **Depends on**: `add-standalone-mode` (archived), `add-themes-and-layout`
  (archived), `add-localization` (the l10n CI job needs one exemption),
  `add-secret-achievements` (reveal moment reused), `redesign-badge-art`
  (SVG pipeline).
- **Unblocks**: `add-couple-link-and-streak` (couple achievements and
  coupon redemption build on this theme and pack);
  `add-health-active-calories` (one activity achievement).
- Code: a new `ios/GarminFood/PartnerTheme/` feature folder; new art in
  `ios/PartnerArt/` (SVG, through the badge-art lint and asset builder); a
  pure `Love/` area in FoodLogCore (pack decoding, message choice, the
  daily minute) so it is unit-testable; AppearanceKit gains a
  pack-unlocked theme id and gradient tokens; `NotificationPlanning` gains
  a text provider and the love-message kind; Gamification gains a
  theme-scoped achievement set; a document type for `.arclove` in
  `Info.plist`; a new alternate app icon.
- No new target, entitlement or background mode. The pack's texts and the
  state are included in backups. Its pictures are not (re-import restores
  them).
