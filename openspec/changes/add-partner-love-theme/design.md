## Context

Written 2026-10-19 on `main` at `43b1db0`, before any code. The owner asked
for this. It is not built yet.

Owner decisions (2026-10-19):

- one kind message a day, at a random time from 08:00 to 13:00, the same
  on weekends;
- no special-date messages;
- every themed behaviour exists only while this theme is on;
- the palette is love pink mixed with Naruto orange;
- Naruto images, badges and cute pictures, with no spoilers past Shippuden
  episode 30;
- development stays free.

What the code already provides:

- **Standalone mode** (`add-standalone-mode`, spec `data-mode`). "Just on
  this phone" makes no Garmin call and hides every Garmin surface.
  `SettingsView` already hides the Vault row when `isStandalone`. The
  partner's install needs nothing new to run without Garmin and without
  the vault.
- **Themes** (`add-themes-and-layout`, AppearanceKit). `BuiltInTheme` is a
  closed enum of 13 `ThemeSpec`s. `ContrastPolicy` and `AccentAdjuster`
  fit colours. `ThemeShareCode` encodes a look. An alternate app icon
  follows the theme. The design-token lint (`tools/lint-design-tokens.sh`)
  keeps colours inside the design system.
- **Notifications** (FoodLogCore `NotificationPlanning`, app
  `NotificationScheduler`). Pure planning, then a diff of identifiers and
  texts against what is pending. A rolling `windowDays = 7`. iOS keeps at
  most 64 pending requests.
- **Achievements and badge art** (Gamification `AchievementEngine`, secret
  achievements with a reveal moment, `BadgeArtCatalog`, SVG motifs in
  `ios/BadgeArt` kept to a small SVG subset by `tools/docs/lint-badge-svg.mjs`
  and turned into imagesets by `tools/docs/build-badge-assets.mjs`).
- **Level tiers** (`LevelTier`): 20 named bands, display only.
- **Localization** (`tools/check-localizations.mjs --scan`, blocking).
  Every `.xcstrings` has source language `en` and needs `cs`. Every SwiftUI
  literal needs a catalog key.
- **Backup** (`add-data-safety`). A deny list decides what is excluded, so a
  new store travels by default.
- **The countdown arithmetic** (`EventCountdown` in FoodLogCore).

## Goals / Non-Goals

Goals: a copy of the app that looks and feels made for one person, built so
that nothing personal and no official picture reaches the public
repository, that works with the app closed, and that never changes the
rules of the existing features.

Non-goals: see the proposal.

## Decisions

### D1: Personal content and official pictures are a file the owner gives her

The repository is public. A compiled-in pack via a CI secret was rejected:
the built `.ipa` is a downloadable Actions artifact of a public
repository, so the messages and pictures would be published.

So the content is a **love pack**: `love-pack` version 1 JSON, extension
`.arclove`, registered as an exported UTI so AirDrop and Files open it in
the app. The owner works in a folder (kept in his private notes vault,
never in this repository):

```text
my-pack/
  pack.json          # texts, ids, settings
  images/            # optional pictures, PNG or JPEG
    love-card-1.jpg
    badge-genin.png
```

`node tools/love-pack/build.mjs my-pack/` checks everything (D11 included)
and writes `my-pack.arclove`: `pack.json` with each picture embedded as
base64. `pack.json` (a synthetic version is in
`tools/love-pack/sample/`, built into `tools/love-pack/sample.arclove`):

```json
{
  "format": "love-pack", "version": 1,
  "packId": "3f0c…",               // stable across re-imports
  "nickname": "Ninja",             // how the app addresses her
  "signature": "Tvůj J.",          // how messages are signed
  "startDate": "2030-01-01",       // day 0 of the daily sequence
  "seed": "b1946ac9…",             // decides each day's minute (D6)
  "daily":     [{ "id": "d001", "text": "…" }, …],
  "openWhen":  [{ "id": "o-sad", "title": "Otevři, až jsi smutná", "text": "…" }],
  "coupons":   [{ "id": "c001", "title": "…", "price": 40 }],
  "countdown": { "date": "2031-06-20", "title": "Svatba" },
  "images":    [{ "id": "i001", "file": "love-card-1.jpg",
                  "slots": ["loveCard", "pictureOfDay"],
                  "lore": ["naruto", "ramen"] }, …]
}
```

`openWhen`, `coupons`, `countdown` and `images` are optional. A feature
with no content is not shown at all.

Every item has an `id`. What she has seen, opened, kept or redeemed is
keyed by `id`, so a re-import that adds, reorders or corrects text never
loses or repeats anything. A pack with another `packId` is a different
pack: the app asks before replacing it.

Limits:

- text ≤ 600 characters, ≤ 2 000 items per list;
- a picture ≤ 2 MiB and at most 4096 px a side, at most 80 pictures;
- the file ≤ 40 MiB, checked before parsing.

Anything else is refused with a reason, and nothing changes.

Storage, in Application Support under `FoodLogCore/Love/` (`LoveStore`):

- `love-pack.json` holds the texts.
- `Images/<id>.<png|jpg>` holds the decoded pictures.
- `love-state.json` holds the revealed ids, favourites, day assignments,
  opened scrolls, the hearts ledger and the import date.

The texts and the state are **included** in backups. Her export to Files
is her only off-phone copy, and losing the message history would hurt more
than any other data. The pictures are **excluded**, so the daily on-phone
snapshot stays small. After a restore the app says "Obrázky chybí –
importuj balíček znovu", and the same `packId` re-imports onto the
restored state.

### D2: The theme is pack-unlocked, not a 14th built-in

`app-theming` promises 13 built-in themes, and `ThemeShareCode` can encode
any of them. The partner theme is a separate `UnlockedTheme.partner`
case. It shows in the picker only while a valid pack is imported, and is
never produced or accepted by a share code. Removing the pack falls back
to GF Teal.

"The theme is on" means exactly: a valid pack is imported **and**
`partner` is the active theme. Every themed behaviour keys off one
`PartnerMode.isActive` value, computed in one place: texts, the greeting,
notification texts, the daily notification, achievements, pictures and
motion.

### D3: Palette: love pink and Naruto orange in one theme

Two brand colours carry equal weight, joined by a gradient:

| Token | Light | Dark | Use |
|---|---|---|---|
| accent (pink) | `#E8457A` | `#FF7FA6` | buttons, tab tint, links, hearts |
| brand2 (orange) | `#F7841E` | `#FF9A3C` | streak flame, rank emblems, highlights |
| gradient | pink → orange, 135° | same, lifted | progress ring, level bar, love card border, hero headers |
| background | `#FFF6F1` (warm cream) | `#1E1219` (plum black) | |
| card | `#FFFFFF` with a faint pink tint | `#2A1A24` | |
| success | `#3FA35B` (leaf green) | `#5CC57A` | |

Final values come from `ContrastPolicy`, like every theme. Macro colours
stay distinguishable from both brand colours (a test checks ΔE). The
gradient is a new AppearanceKit token, `brandGradient`. Other themes
return a flat accent for it, so no other screen changes. The design-token
lint allows it.

### D4: Art direction and inventory

**Style.** Cute, round and warm: chibi proportions, thick soft outlines in
deep plum (`#4A2338`), flat fills, pink and orange with leaf green as
the third colour. Small sparkles and hearts are the accents. Each piece
reads at 44 pt and works on cream and on plum black.

**Original only in the repository; official pictures through the pack.**
The official Naruto pictures are a main part of the theme. The owner
chooses them and they reach her phone in the pack (D1). Every built-in
piece is drawn for this app. Naruto-*inspired* imagery is fine: ninjas, a fox, a toad,
ramen, scrolls, kunai, shuriken, sakura, a spiral, headbands. Official
characters, the official logo, symbols copied from the series and the
series' fonts are not used. Built-in art lives in `ios/PartnerArt/` as
SVG in the badge subset, goes through `lint-badge-svg.mjs` and
`build-badge-assets.mjs`, and is listed in a catalog test.

| Piece | Where |
|---|---|
| App icon: a heart with a spiral cut-out and a small shuriken, pink→orange | home screen |
| Chibi ninja fox hugging a heart | empty Today love card, onboarding to the theme |
| Two chibi ninjas back to back, a heart between them | message box header; couple panel later |
| Ramen bowl with a heart-shaped fish-cake swirl | food-log empty state, "Ichiraku" achievement |
| Love-letter scroll with a heart wax seal (closed and open) | "Otevři, až…" |
| Toad holding a heart | streak at risk card |
| Sakura branch with a kunai | notifications settings, section headers |
| Shuriken heart (spinning) | the log-confirm burst |
| Night sky with a crescent and heart stars | evening greeting background |
| 7 rank emblems (Akademie … Kage), headband plate shape with a heart | level badge |
| 18 achievement badges (D9) | achievements |
| Coupon ticket with a stamp | coupons |

**Pack pictures.** A pack picture names the slots it may appear in:

- `loveCard`
- `messageBoxHeader`
- `pictureOfDay`: one picture a day on the love card, drawn from the
  pictures that allow it, seeded by date, never the same two days in a
  row
- `emptyState`
- `rankEmblem:<rank>`
- `badge:<achievementId>`: masked into the achievement's frame, which
  keeps its rarity border

Where several pictures allow a slot, it rotates daily. Built-in art fills
any slot no picture claims. So the official Naruto pictures the owner
chooses show up across the theme, and the app still looks complete
without any.

**Motion.** Confirming a log entry plays a heart burst with 6–8 sakura
petals and one spinning shuriken heart, ≤ 700 ms, behind the success
check and never covering it, with the haptic pattern `heartbeat` (two
soft taps). Unlocking a level shows the new rank emblem with a short
pink→orange shimmer. Under Reduce Motion each is a static frame. VoiceOver
reads illustrations as decorative, except the picture of the day ("Obrázek
dne").

### D5: Czech only: a content table, one l10n exemption

The theme's text is Czech and only Czech. Putting it in
`Localizable.xcstrings` would trip the `cs`/`en` completeness check for
hundreds of strings with no English. So:

- Generic theme text goes in one bundled resource,
  `PartnerTheme/Resources/partner-theme.cs.json`: rank names, greetings,
  themed notification variants, achievement titles and descriptions,
  empty states. It is read through a small `PartnerText` table with
  `{nickname}`, `{signature}` and `{count}` placeholders, and shown with
  `Text(verbatim:)`.
- `check-localizations.mjs --scan` gets one exemption: files under
  `ios/GarminFood/PartnerTheme/` may use `Text(verbatim:)` with a
  `PartnerText` value. Any other literal there is still an error.
- The few rows outside the theme stay normal en+cs strings, because they
  show on any phone: Settings > Appearance > "Import love pack…", the
  import result, and the remove confirmation.
- Czech plurals (1 srdíčko, 2–4 srdíčka, 5+ srdíček, 0 srdíček) come from a
  tiny pure `CzechPlural` helper with tests.

### D6: The daily message: which one, and at what minute

**Which.** The day index is `n = days(startDate → today)` in the device
calendar. The message is the next id of a **seeded permutation** of the
`daily` ids not yet revealed. Each day consumes one, so no message repeats
until all have been shown. When the pool is empty, it refills from the
favourites first, then from everything, and Today says "Všechny vzkazy už
znáš – tady je jeden z tvých oblíbených ❤️". A repeat is never mistaken
for a bug. A re-import adds new ids to the unrevealed pool.

To be stable across re-plans, the day → id assignment is **recorded** in
`state.json` when a day is first planned. The scheduler plans 7 days
ahead, so tomorrow's message must already be decided. A recorded day never
changes, even if the pack is re-imported. Only unplanned days are drawn.

**When.** The minute is `08:00 + (H(seed, yyyy-mm-dd) mod 300)`, giving
08:00–12:59, every day of the week. H is the first 8 bytes of SHA-256. It
is pure, and it gives the same answer after a restore or a re-plan. If
that minute falls within 10 minutes of another planned reminder that
day, it moves to the next free minute, still before 13:00, so no two
notifications buzz together. On a DST change day the wall-clock minute is
kept.

**Reveal.** A day's message is revealed at its minute, or when she taps
its notification, whichever is first. Revealing does not depend on the
notification firing: with notifications off, Today shows the message from
its minute anyway. Before the minute, Today shows only "Dnešní vzkaz
dorazí dopoledne 💌", never the text. The message box shows revealed
messages only, newest first, with the date and a heart toggle.

### D7: Notifications: the love message wins the budget

iOS keeps at most 64 pending requests. The love message adds 1 per day.
The planner orders the window by priority:

1. the love message for days 0–6;
2. today's other requests;
3. future days of the other kinds, nearest first.

It truncates at 60, leaving 4 free for one-off requests. A test pins the
count with every kind switched on.

Identifier `love.daily.<yyyy-mm-dd>`, title "Pro {nickname} ❤️", body the
message, thread `love`. The pack's picture of the day for that date is
attached when it is ≤ 1 MiB (`UNNotificationAttachment` from a copy in
`tmp/`; no entitlement). Tapping it opens
`garminfood://love/day/<yyyy-mm-dd>`: the message box at that day,
revealed. A planned day's text is final (D6), so the text diff never
rewrites a pending love message.

### D8: Themed texts for existing notifications

A `NotificationTextProvider` seam is added to `NotificationPlanning`. The
default provider returns today's texts unchanged. The partner provider
returns a variant from `partner-theme.cs.json` for each kind. There are
3–7 variants per kind, chosen by `H(seed, date, kind) mod count`, so the
text is stable for the day and the text diff does not churn pending
requests. Supplement reminders keep the supplement name in the body, and
only the title is themed. **When** a reminder fires is not touched.

Examples (final wording in the table):

- breakfast: "Ninja potřebuje snídani 🍙 Co sis dala, {nickname}?"
- lunch: "Polední mise: oběd! Ramen se počítá 🍜"
- streak at risk: "Tvoje cesta ninji je v ohrožení – stačí zapsat jedno jídlo ❤️"
- daily challenges: "Nové mise na dnešek čekají, šampionko 🥷"

### D9: Theme-only achievements and hearts

A separate `PartnerAchievementSet` in Gamification is evaluated by
`AchievementEngine` only while `PartnerMode.isActive`.

- Counting starts at the pack's import date, so nothing unlocks in a burst
  on day one.
- It re-evaluates from the local logs plus `love/state.json`.
- Switching the theme off hides the set and keeps its unlocks. Switching
  back catches up with anything the data earned meanwhile.
- Secret ones use the existing reveal moment.

They pay **srdíčka**, not XP. XP is pinned by `XPBudgetTests` and the
level curve is solved from the budget. Hearts are a separate ledger in
`love/state.json`: earned entries and spent entries, with the balance
derived, never stored. Redeeming a coupon shows a stamped "svitek" with the
coupon and the date, to be shown in person.

Starting set (titles final in the table, lore-tagged):

| id | Název | Rule (counted since import) | ❤️ |
|---|---|---|---|
| `p.firstnote` | První svitek | First daily message revealed | 5 |
| `p.week` | Týden lásky | Messages revealed on 7 days in a row | 10 |
| `p.box30` | Sběratelka vzkazů | 30 messages revealed | 15 |
| `p.box100` | Knihovna lásky | 100 messages revealed | 40 |
| `p.box365` | Rok vzkazů | 365 messages revealed | 100 |
| `p.morning` | Ranní ninja | Opened the day's notification within 15 min, 5 times | 15 |
| `p.genin` | Genin | Logged food 3 days in a row | 5 |
| `p.chunin` | Chuninská zkouška | All 3 main meals logged on 7 days | 20 |
| `p.jonin` | Jonin | 30-day streak | 40 |
| `p.kage` | Kage | 100-day streak | 100 |
| `p.ramen` | Ichiraku s láskou | Logged a food matching "ramen" or "nudle" | 10 |
| `p.water` | Živá voda | Water goal met on 7 days | 15 |
| `p.clone` | Technika stínových klonů | The same meal preset logged on 5 days | 10 |
| `p.active` | Ohnivá vůle | Active-calorie goal met on 5 days (needs `add-health-active-calories`) | 15 |
| `p.scroll` | Otevřený svitek | Opened an "Otevři, až…" scroll | 5 |
| `p.coupon` | První kupón | Redeemed a coupon | 5 |
| `p.heart10` (secret) | Dattebayo! | Tapped the love-card heart 10 times in a row | 10 |
| `p.night` (secret) | Noční hlídka | Opened the message box after 23:00 | 5 |
| `p.allfav` (secret) | Srdce na dlani | 20 favourites | 15 |

`p.scroll` and `p.coupon` exist only when the pack has scrolls or coupons.
`add-couple-link-and-streak` adds the couple achievements.

### D10: Today

With the theme on, the Today header becomes "Dobré ráno / Dobré odpoledne
/ Dobrý večer, {nickname}", with the evening sky after 18:00.

Below it is one **love card** with a pink→orange gradient border. It
shows today's message (or "dorazí dopoledne"), the picture of the day,
and, when the pack has one, the countdown ("Do svatby zbývá 213 dní",
computed with `EventCountdown`). The card is a layout card id, so she can
move or hide it like any other.

### D11: No spoilers: an allow-list, owner-reviewed

They are at Naruto Shippuden episode 30. A deny-list would itself name
what happens later, so it is not used, and this document names nothing
beyond the allow-list either.

- Every content entry in `partner-theme.cs.json`, every built-in
  illustration's catalog entry, and every pack picture that references
  the series carries `"lore": [...]`.
- `tools/love-pack/lore-allowlist.json` lists the allowed terms. Its header
  records the episode boundary, `"seenThrough": "Shippuden 30"`. It can
  only grow as they keep watching.
- CI (`localization` job) and `build.mjs` fail when a tag is not on the
  list. CI also fails on an untagged entry whose text has a capitalised
  word that is neither a sentence start nor on a small Czech common-words
  list. That catches a forgotten tag. It does not judge meaning.
- Content rules: no plot events, no pairings, no character fates, even
  ones already seen. **Characters of the arc being watched now are not
  used at all**, so nothing can hint at how it ends. When in doubt, use
  generic ninja imagery.
- **The owner reviews the list (task 1.3) and his own pictures.** A
  picture can't be linted. Its tags are his promise.

The proposed starting list, for the owner's review:

- **People:** Naruto, Sakura, Kakashi, Iruka, Tsunade, Jiraiya, Rock Lee,
  Guy, Konohamaru, Teuchi and Ayame (Ichiraku), Pakkun, Gamakichi,
  Gamabunta.
- **The fox:** "Kyuubi" / "Devítiocasý".
- **Places and things:** Konoha (Listová vesnice), Ichiraku, the Hokage
  monument, the Academy, a training ground, the frog wallet (Gama-chan),
  a ninja headband, scrolls, kunai, shuriken.
- **Techniques:** Rasengan, Stínoví klonové (Kage Bunshin), Sharingan,
  Henge, Kuchiyose.
- **Ranks:** Akademie, Genin, Chunin, Jonin, ANBU, Sannin, Kage, Hokage.
- **Phrases:** "Dattebayo!", "cesta ninji", "Tým 7", "ramen".

## For the owner: building the pack

- Write in `my-pack/pack.json`. Never reuse an `id`. Add new messages at
  the end.
- Aim for 365 daily messages. Fewer works: once used up, they repeat with
  favourites first.
- Pictures: up to 80, each ≤ 2 MiB. Give each one `slots` and `lore`
  tags. Check each picture against the episode yourself.
- `node tools/love-pack/build.mjs my-pack/` checks everything and writes
  the `.arclove`. AirDrop it to her phone. It opens in the app, which shows
  what changed ("+40 vzkazů, +6 obrázků").

## Risks / Trade-offs

- **The repository is public.** Official pictures are private to her
  phone (owner, 2026-10-19). They travel only in the pack, never through
  this repository or its build artifacts, which anyone can download.
- **The phone left closed for over 7 days** stops getting notifications
  after day 7. On open, the message box still shows every day's message.
  The existing BG refresh re-plans when iOS grants it.
- **Clock tampering** reveals future messages. Accepted.
- **The spoiler lint is heuristic.** The owner's review of the list and of
  his pictures is the real gate.
- **Czech-only content outside `.xcstrings`** gives up Xcode's plural
  engine. `CzechPlural` covers the forms used.
- **Her AltStore refresh**: a free account re-signs every 7 days. If it
  lapses, the app won't launch until it is refreshed. Data survives,
  because the app is re-signed in place. See `docs/partner-phone-setup.md`.
- **Pack size**: 80 pictures at 2 MiB is ~210 MiB of base64 before the 40
  MiB cap refuses it. `build.mjs` reports the size and suggests
  downscaling.

## Migration Plan

No migration. Nothing changes until a pack is imported. Removing the pack
(Settings > Vzhled > Odebrat balíček) returns the app to GF Teal. The
state file is kept, so re-importing the same `packId` restores everything.

## Open Questions

1. Should the agent draft a starter set of daily messages in Czech for the
   owner to rewrite, kept outside the repository?
2. Keep the optional extras (coupons, "Otevři, až…" scrolls, the
   countdown), or drop them?
3. Her name on the home screen: keep "Jirka's Arc", or a second build with
   its own display name (for example "Pro Ninju")?
