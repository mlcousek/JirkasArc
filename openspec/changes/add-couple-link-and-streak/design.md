## Context

Written 2026-10-19 on `main` at `43b1db0`, before any code.

Owner decisions (2026-10-19):

- a couple day is at least one food entry each;
- couple freezes, yes;
- development stays free, so there is no push.

What VaultKit provides (`add-vault-connection`, `add-training-checkins`):
`GitHubContentsClient` with `getFile(_:ifNoneMatch:)` (conditional GET)
and `createFile` (PUT without `sha`: create or 422, never overwrite);
`VaultTransport` (`fetch`, `createOnly`, `probe`); `DurableQueue`;
`CreateOnlyFileUploader`; `VaultTokenStore` (Keychain);
`DeviceIdentity` (`ios-` + 8 hex); `VaultPathPolicy`; `VaultStatus`
(loud auth, quiet rest). `HubPath.root` is a constant,
`Sport/Training/_hub`. There is **no directory listing**: every read is a
known path.

## Decisions

### D1: A separate private repository, the same transport

A Cloudflare Worker or Firebase was considered: new infrastructure, a new
account, and a new failure mode, for two users. GitHub is already trusted,
rate limits (5 000 requests/hour per token) are far above two phones'
needs, and create-only writes plus conditional reads are exactly the
pattern needed.

The couple hub is a new private repository the owner creates. Its token is
fine-grained: one repository, Contents read and write, nothing else. The
same token goes on both phones (in each phone's Keychain under a new
service, `GarminFood.couple`). It cannot reach the notes vault.

`HubPath` gains a root parameter: `HubRoot.vault` (unchanged value) and
`HubRoot.couple` (`couple`). The vault's path policy and tests are
untouched. `CouplePathPolicy` allows writes only to
`couple/<ownMemberId>/days/<yyyy>/<yyyy-mm-dd>.json`,
`couple/<ownMemberId>/inbox/<seq 8 digits>.json` and
`couple/<ownMemberId>/member.json`, and reads only of the two members'
folders with the same shapes. Everything else is refused before a request,
like the vault.

### D2: Files with predictable names, so no listing is needed

- `member.json`: created at pairing (display name, app version, created
  date). Read once.
- `days/<yyyy>/<date>.json`: `{ "date", "doneAt", "allMeals": bool }`.
  Created the first time the day's part is done. `allMeals` is a fact at
  creation. When it becomes true later that day, a second create-only file `<date>.b.json` records the
  upgrade (create-only never edits, and the reader takes the union).
- `inbox/<seq>.json`: `{ "seq", "kind": poke|note|coupon|achievement,
  "at", "body" }`. `seq` starts at 1 and increments locally. The reader
  keeps the last seen seq per member and fetches `seq+1` until a 404.

Reading the partner's last 8 days is 8 conditional GETs, mostly 304. Each
refresh is ~10 requests.

Writes go through `DurableQueue` + `CreateOnlyFileUploader`: offline
writes wait, a 422 on an inbox file is resolved by one read (same body:
done; different body: the seq was used by a lost write, so take the next
seq), like the vault backup's "seen" rule.

### D3: The couple streak

Day = the device's calendar day (both phones in Europe/Prague; a
different time-zone member is out of scope). A member's day is done when
a `days/<date>.json` exists for it.

`CoupleStreak` (pure, FoodLogCore `Couple/`), from the two members' sets of
done dates and `today`:

- A date is **shared** when both are done.
- A date is **pending** when exactly one is done and `today ≤ date + 1`
  (the partner's phone may not have synced yet). Pending never breaks.
- A date with neither done, or one done and the grace over, is
  **missed**. A missed date is covered by a freeze if one is available,
  otherwise the streak ends there.
- Freezes: one earned at every 7th consecutive shared day, at most 2 held,
  consumed automatically for the oldest missed date first.
- The current streak counts back from the newest shared-or-pending date.
  A pending today does not add a day until it is shared.

Both phones run the same function on the same files, so they show the same
number. The function is pure and tested with the same fixtures from both
sides.

### D4: What "done" means and what is shared

"Day done": at least one food entry logged that day (the personal streak's
rule; owner decision). `allMeals`: breakfast, lunch and dinner each have
an entry.

Shared fields are exactly those in D2. A test decodes every outgoing file
and fails on any extra field. A food name, a calorie number or a weight
would have to pass that test to leave the phone.

### D5: Refresh and notifications

Read on foreground, every 2 minutes while in the foreground, and in the BG
refresh. New inbox items and a newly shared day become local notifications
(thread `couple`). In the partner theme, texts come from its table ("Tvůj
ninja ti poslal šťouchnutí 🥷❤️"). On his phone they are en/cs from the
catalog. A poke is limited to 3 a day on the sender's side.

Status follows the vault's rule: a rejected token (401/403) is loud ("Propojení
s partnerem přestalo fungovat"), and offline or rate-limited is quiet with
the last-seen time.

### D6: Pairing by QR, in person

His phone shows a QR code with `{ v:1, repo, token, coupleId, members:
[a, b], you: b }`. Her phone scans it (the existing DataScanner, QR
symbology), stores the token in its Keychain, writes `member.json` and
runs a probe. The QR is shown only after Face ID / passcode
(`LocalAuthentication`, no entitlement), with a warning not to screenshot
it. Re-showing it is allowed: it carries nothing beyond what both phones
already hold. Rotating the token is done on GitHub and re-paired.

### D7: One transport seam

The transport sits behind a `CoupleTransport` protocol (GitHub today, an
in-memory one in tests). If the paid program is ever bought, a CloudKit
shared zone with push could replace it without touching the streak or the
messages. That is not planned.

## Risks / Trade-offs

- **Latency on the free tier.** A poke sent while her app is closed
  arrives when iOS next runs the BG refresh, or when she opens the app.
  Stated in the UI ("doručeno při příští synchronizaci").
- **The token is on two phones.** It is scoped to one repository with
  nothing but couple files in it. Losing a phone means rotating it.
- **Clock skew** between the phones could make "pending" end early. The
  grace is a whole extra day.

## Migration Plan

None. Unpaired, nothing changes. The two stores (`couple/state.json`,
`couple/outbox` via `DurableQueue`) are in backups. The token is not
(BackupSecretPolicy).

## Open Questions

1. Should the couple panel live on his Today screen, or only in Settings >
   Partner?
