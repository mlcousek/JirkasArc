# Setting up the partner theme on her phone

Installing the app on a second iPhone is in
[install-second-phone.md](install-second-phone.md): AltStore or SideStore
under her own Apple ID, the 7-day refresh, and keeping her data safe. This
page covers what comes after that: turning on the partner theme
("Srdce ninji", `openspec/changes/add-partner-love-theme`).

## 1. First launch: just on this phone

On the first launch the app asks how it will be used. Pick **"Just on this
phone"**. That is standalone mode: no Garmin and no vault. She can set her
daily goals or skip that step.

Set the app's language to Czech in iOS Settings > Jirka's Arc > Language.
The theme's own text is Czech in either language.

## 2. Build the love pack (on your computer)

Keep the pack folder **outside this repository** (in your notes vault, for
example). See [tools/love-pack/README.md](../tools/love-pack/README.md) for
the format.

```text
my-pack/
  pack.json        nickname, signature, startDate, seed, daily messages, extras
  images/          the pictures you chose, PNG or JPEG
```

- One message is shown per day, at a random time from 08:00 to 13:00. Aim
  for 365. If you write fewer, they repeat once used up, favourites first.
- Every picture needs `lore` tags (`[]` if it shows nothing from the
  series). Check each picture yourself against the episode you have
  reached. Tags must be on
  [lore-allowlist.json](../tools/love-pack/lore-allowlist.json).

```sh
node tools/love-pack/build.mjs path/to/my-pack     # writes path/to/my-pack.arclove
```

The builder refuses anything the phone would refuse, and names the
problem.

## 3. Give it to her phone

AirDrop the `.arclove` file to her phone (or save it to Files) and open it.
The app shows how many messages and pictures it holds. Tap **Importovat**.
The first import also switches on the theme and, with "Match app icon to
theme" on, the heart icon.

The same pack can be imported again later with more messages or pictures.
Nothing she has already read is lost. A pack with a **different** `packId`
asks first, and its history starts over.

## 4. Notifications

Turn on at least one reminder in Settings > Notifications. That is what
asks iOS for permission. Without permission the messages still appear on
Today at their time, but no notification arrives.

Each day's message is scheduled up to 7 days ahead. If the app stays closed
for longer than that, the notifications stop until it is opened again. The
message box still fills in for every missed day.

## 5. Day to day

- **Today:** her greeting, the day's message once its time has come, the
  picture of the day, the countdown, and links to "Krabička vzkazů",
  "Svitky srdce" and the "Otevři, až…" scrolls.
- **After each logged meal:** a heart burst.
- **Reminders:** in the theme's words, at the same times as before.
- **Achievements:** pay hearts, which buy the coupons you wrote. A redeemed
  coupon is a dated, stamped scroll she can show you.

## Backups

Her backup export (Settings > Data) carries the messages she has read and
her hearts, but not the pictures. After restoring onto a new phone, import
the same pack again to bring the pictures back.

## Removing it

Settings > Vzhled > Balíček lásky > Odebrat balíček lásky. The app returns
to GF Teal. What she has read is kept, and comes back if the same pack is
imported again.
