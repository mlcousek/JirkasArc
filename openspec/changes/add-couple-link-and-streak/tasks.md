Every task ends with CI green: `swift test` for VaultKit and FoodLogCore, the
app and widget `xcodebuild`, `localization`. All new user-facing text
outside the partner theme is in English and Czech. Nothing personal in the
repository: synthetic repository `example-owner/example-couple`, members
`ios-0000abcd` and `ios-0000beef`, dates in 2030, planted tokens assembled
at run time. The vault's `HubPath` behaviour, `VaultPathPolicy` and their
tests are unchanged. No new target, entitlement or background mode.
Branch `mlcousek/couple-link` on `main`, after `add-partner-love-theme`.
Relative size: S / M / L.

## 1. Design and decisions (S)

- [ ] 1.1 Proposal, design, specs, this file; `openspec validate add-couple-link-and-streak --strict`.
- [x] 1.2 Owner decisions 2026-10-19: one food entry each, freezes on, free tier. Open: where his panel lives.
- [ ] 1.3 Owner creates the private couple hub repository and a fine-grained token (one repository, Contents read/write). Not recorded anywhere in this repository.

## 2. VaultKit: a second root (M)

- [ ] 2.1 `HubRoot` (`vault` = `Sport/Training/_hub` unchanged, `couple` = `couple`); `HubPath` and `GitHubContentsClient` take it; every existing call site passes `.vault`.
- [ ] 2.2 `CouplePathPolicy` (own folder writes, two-member reads, exact shapes).
- [ ] 2.3 Tests: the policy's allowed and refused shapes; the vault's existing tests untouched and green.

## 3. Couple domain, pure (M)

- [ ] 3.1 FoodLogCore `Couple/CoupleFiles.swift`: member, day-done (+ `.b` upgrade), inbox item; encoders that emit only the allowed fields; a test that fails on any extra field.
- [ ] 3.2 `Couple/CoupleStreak.swift` (shared, pending with next-day grace, missed, freezes earned at 7, cap 2, oldest first).
- [ ] 3.3 `Couple/CoupleInbox.swift`: seq allocation, read-until-404, dedupe by seq, the 422 rule (same body done; different body take the next seq), 3 pokes a day.
- [ ] 3.4 Tests from both members' sides with the same fixtures.

## 4. The app (L)

- [ ] 4.1 `CoupleService`: `DurableQueue` + `CreateOnlyFileUploader` for writes; refresh on foreground, every 2 min in the foreground, in BG refresh; status loud on 401/403, quiet otherwise.
- [ ] 4.2 Day-done trigger from the food log (first entry of the day; the `allMeals` upgrade).
- [ ] 4.3 Pairing: QR show behind `LocalAuthentication`, QR scan via the existing DataScanner, Keychain service `GarminFood.couple`, probe, unpair.
- [ ] 4.4 Settings > Partner (en + cs): status, couple streak, partner's day (done / all meals), send poke or note, history.
- [ ] 4.5 Her side, partner theme: couple streak on the love card, pokes and notes into the message box, themed notification texts.
- [ ] 4.6 Couple achievements into `PartnerAchievementSet`; coupon redemption and achievement unlocks sent as inbox items.
- [ ] 4.7 `StoreCatalog`: couple state and queue in backups; the token never (`BackupSecretPolicy` test).

## 5. Verify (S)

- [ ] 5.1 CI green on the PR.
- [ ] 5.2 Two real phones: pair; both log, so streak 1 on both; poke while her app is closed arrives on refresh (record the delay); 401 after revoking the token is loud; unpair stops requests.
