# Love pack

The partner theme (`openspec/changes/add-partner-love-theme`) gets everything
personal from one file, `*.arclove`, that you AirDrop to her phone. It holds
the daily messages, her nickname, your signature, the optional extras, and
the pictures you chose.

**Keep your pack folder outside this repository** (in your notes vault, for
example). This repository is public. Nothing personal, and no picture she
sees, may be committed.

## Folder

```text
my-pack/
  pack.json
  images/
    love-card-1.jpg
    badge-genin.png
```

`sample/` is a working synthetic example.

## pack.json

| Field | Required | Notes |
|---|---|---|
| `format`, `version` | yes | `"love-pack"`, `1` |
| `packId` | yes | Never change it: a new id is a new pack and starts her history over. |
| `nickname` | yes | How the app greets her. |
| `signature` | no | How messages are signed. |
| `startDate` | yes | `yyyy-MM-dd`. Messages start on this day, or on the import day if that is later. |
| `seed` | yes | Any text. Decides each day's minute (08:00–12:59) and the order of the messages. Never change it. |
| `daily` | yes | `[{ "id", "text", "lore"? }]`: one per day, none repeated until all are used. |
| `openWhen` | no | `[{ "id", "title", "text" }]`: "Otevři, až…" scrolls. |
| `coupons` | no | `[{ "id", "title", "price" }]`: bought with hearts. |
| `countdown` | no | `{ "date", "title" }`: shown on the love card. |
| `images` | no | `[{ "id", "file", "slots", "lore" }]` |

Rules:

- **Ids.** Use letters, digits, `.`, `_` and `-`, up to 64 characters. Never
  reuse an id. Add new messages at the end. Her history is kept by id, so
  re-importing never loses or repeats anything.
- **Text length.** Messages can be up to 600 characters. Titles, the
  nickname and the signature can be up to 120.
- **Pictures.** PNG or JPEG, up to 2 MiB each, up to 4096 px a side, up to
  80 in a pack. The whole file can be up to 40 MiB.
- **Slots** (where a picture may appear):
  - `loveCard`
  - `messageBoxHeader`
  - `pictureOfDay`
  - `emptyState`
  - `rankEmblem:<akademie|genin|chunin|jonin|anbu|sannin|kage>`
  - `badge:<achievement id>`, for example `badge:p.genin`

  If several pictures name the same slot, they rotate daily.

## No spoilers

Every picture needs `lore` tags, `[]` when it shows nothing from the series.
Messages may have tags too. Every tag must be on `lore-allowlist.json`, which
only lists things already seen (`seenThrough`). The builder refuses anything
else. It can't look at a picture, so tagging the picture honestly is up to
you. When you watch further, add terms to the list and bump `seenThrough`.

## Build

```sh
node tools/love-pack/build.mjs path/to/my-pack            # writes path/to/my-pack.arclove
node tools/love-pack/build.mjs path/to/my-pack --out x.arclove
```

Then AirDrop the `.arclove` file to her phone and open it in the app. The
app shows what changed ("+40 vzkazů") before anything is applied.

`node tools/love-pack/build.mjs --sample` rebuilds `sample.arclove`.
`node tools/love-pack/test.mjs` is the self-test, which also runs in CI.
