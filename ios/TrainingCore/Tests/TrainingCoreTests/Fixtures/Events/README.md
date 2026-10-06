# Event fixtures (app side, synthetic)

- **What:** `events.v1.app.jsonl` -- seven events in the envelope v1 this app
  writes (`add-training-checkins` design D2): two morning check-ins for the
  same day (the later one wins), two habit ticks (on, off), an RPE and a
  note for one session, and a rest-day check-in without a session.
- **Synthetic:** the session and habit ids come from the vault's synthetic
  2030 example season (`../Contract/vault/projection.v1.example.json`); the
  device id `ios-0000beef` and every id are made up. No real names, dates or
  data.
- **Golden:** `HubEventTests` encodes the same events and compares the bytes
  with this file exactly (sorted keys, unescaped slashes, `\n` after every
  line, LF only -- see `.gitattributes`), and decodes it back.
- **`plan-commands.v1.app.jsonl`** (add-plan-editing design D2): seven
  plan commands and a retraction in the same envelope -- a move, a swap,
  a skip with a reason and one without, an unskip, a rule override, and
  the retraction of the reasonless skip. Same ids and device, same
  byte-exact rule. `JSONEncoder`'s sorted keys compare by code unit
  (case-sensitively) on the platforms this app runs on, which is why a
  swap's payload reads `a, aDate, b, bDate, baseRevision, week` -- an
  upper-case `D` sorts before a lower-case `a`.
- **`checkin-pains.v1.app.jsonl`** (add-checkin-pain-score design D1):
  three check-ins with `pains` -- a list, an empty list and a note that
  needs escaping.
- **`gates.v1.app.jsonl`** (add-training-gates-and-load design D1): the
  vault example's own six lines for the new facts -- seq 25 `test.gate`,
  26 and 27 `session.done`, 28 a `session.rpe` with `pains`, 32
  `race.result`, 33 `session.fuel` -- with the vault's ids, device
  (`ios-0a1b2c3d`), clock and values, as THIS app encodes them: keys
  sorted, nothing else changed. `HubEventTests` builds the same events in
  Swift and compares the bytes; decodes each mirrored line and encodes it
  again to the same bytes; and compares that with the mirrored line as a
  JSON object (no key added, none dropped -- which is why `officialTime`,
  `pains` on a rating that did not ask, and `during` / `after` of a site
  are left out when unknown, as the vault's lines leave them out). Whole
  numbers have no fraction (`4`, `10`, `90`); `1.5` and `42.2` are exact
  decimals. Regenerate it from the mirrored example when the vault changes
  those lines -- never by hand.
- **Checked against the vault:** the vault's event contract v1
  (`add-hub-ingest`) validator accepts every line (2026-09-29; the plan
  commands on 2026-09-30, with the validator of the vault's main branch). Its own
  fixtures are mirrored verbatim in `../Contract/vault/`. When the vault
  changes the contract, reconcile `Events/HubEvent.swift` and regenerate
  this file.
