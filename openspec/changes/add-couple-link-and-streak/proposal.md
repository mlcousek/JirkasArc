## Why

With the app on both phones, the owner wants it to connect them: be
"friends" in the app, keep a **couple streak** like Duolingo's friend
streak (it grows only on days you both did your part), and send each other
small things: a poke, a note, a redeemed coupon.

There is no backend, and the free tier has no push and no iCloud. The app
already speaks to a private GitHub repository through VaultKit, with
create-only writes, conditional reads and a durable queue. A second,
small private repository, the **couple hub**, used by both phones, gives a
shared place for $0 and reuses that transport as it is.

## What Changes

- **Pairing.** On his phone: Settings > Partner > "Propojit" shows a QR
  code holding the couple hub's repository, a fine-grained token limited to
  that one repository, the couple id and the two member ids. Her phone
  scans it with the existing scanner. Both phones run "Test" against the
  hub. It works on standalone installs (it is not Garmin and not the
  vault). Unpairing deletes the token and the local couple state on that
  phone.
- **The couple hub's files.** Each phone writes only into its own folder,
  create-only, with names the other phone can predict:
  `couple/<memberId>/days/<yyyy>/<yyyy-mm-dd>.json` (written once, when
  the day's part is done) and `couple/<memberId>/inbox/<seq>.json` (pokes,
  notes, coupons, achievements, sent in order). The other phone reads them
  by name (a 404 means "not yet"), so no directory listing is needed.
- **The couple streak.** A day counts when **both** members have a "day
  done" file for it: at least one food entry that day, the same as the
  personal streak (owner decision 2026-10-19). A day is never broken while the
  partner's phone simply has not reported yet ("čeká na partnera" until
  the end of the next day). It breaks only once both phones have spoken,
  or after that grace. One **couple freeze** is earned per 7-day
  milestone, at most 2, used automatically. Both phones compute the same
  number from the same files.
- **What is shared.** By default: day done (yes/no), all three meals logged
  (yes/no), level, partner achievements, notes, pokes and coupons. **Never**: foods,
  calories, active calories, weight, water amounts, fasting, supplements,
  health data.
- **Things to send.** "Šťouchnutí" (a poke from 6 preset kind lines, at
  most 3 a day), "Vzkaz" (a note of up to 280 characters), coupon
  redemptions (the partner theme's coupons reach his phone: "Uplatnila
  kupón: Večeře podle tvého výběru"). Received items become a local
  notification at the next refresh and stay in the message box (hers) or
  Settings > Partner (his).
- **Freshness, stated plainly.** No push: the phones read the hub on
  foreground, every 2 minutes while in the foreground, and in the existing
  BG refresh (iOS decides when: minutes to hours). The owner keeps
  development free (2026-10-19), so there is no push.
- **Couple achievements** in the partner set ("Tým 7": 7-day couple
  streak; "Spojená srdce": 30; "Hokage lásky": 100; "Synchronizovaná mise":
  both logged all three meals on the same day, 5 times; "Ranní pozdrav":
  sent a poke before 9:00 on 7 days). On his phone they show as a small
  "Partner" panel, not as his achievements.

## Capabilities

### New Capabilities

- `couple-link`: pairing, the couple hub transport and path policy, what
  is shared, refresh, unpairing.
- `couple-streak`: the shared-day rule, the grace for late reports,
  freezes, the display on both phones.
- `couple-messages`: pokes, notes, coupon and achievement events, their
  notifications and limits, and the couple achievements that join the
  partner set.

### Modified Capabilities

- None. `partner-achievements` exists only once `add-partner-love-theme`
  is archived, so the couple achievements are specified in
  `couple-messages`.

## Non-goals

- More than two members, or friends beyond the couple.
- Sharing food details or any health value (see "What is shared").
- Real-time delivery on the free tier.
- A web or desktop view of the couple hub.
- Using the owner's notes vault for this: the couple hub is a separate
  repository, so her token can never touch his vault.

## Impact

- **Depends on**: `add-vault-connection` (archived; GitHub client, durable
  queue, create-only uploads), `add-partner-love-theme` (coupons, message
  box, partner achievements).
- **Unblocks**: nothing planned.
- VaultKit: `HubPath`'s fixed root becomes a per-client `HubRoot` (the
  vault keeps `Sport/Training/_hub`; the couple hub uses `couple`). A new
  `CouplePathPolicy` allows writes only to the own member folder.
- The app: a `Couple/` feature folder, Settings > Partner (en + cs), the QR
  scanner reused for pairing, two new stores (in backups, without the
  token).
- No new target, entitlement or background mode.
