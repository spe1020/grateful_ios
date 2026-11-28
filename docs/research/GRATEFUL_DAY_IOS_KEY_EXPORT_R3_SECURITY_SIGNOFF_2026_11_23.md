---
title: "Grateful Day iOS — Key export r3: Audit security requirements for Seth's D1–D5"
tags: [grateful-day, ios, keys, export, security, audit]
status: active
created: 2026-11-23
---

**Author:** Audit. **For:** Prep, to fold into `PLANS/GRATEFUL_DAY_IOS_KEY_EXPORT_AND_SAVE_SYNC_PRODUCT_2026_11_22.md` r3, §1.6 and §2.4.
**Grounded in:** `origin/main` `2a424a2`: `PublishDisclosure.swift:48-66`, `JournalRepository.swift:187-204, 283-286`, `SyncService.swift:139-140`, `GratefulDayApp.swift:77-88`, `Account/KeyVault.swift:33, 57, 156`.
**Seth's decisions:** event a30708b0 (2026-11-23).

## The r2 security requirements stay

S1–S7 and the r2 tightenings in §1.6 all still apply. None of Seth's decisions loosens any of them.

## D2: a device passcode is required

- The only gate is `LAContext().evaluatePolicy(.deviceOwnerAuthentication, …)`.
  - `LAError.passcodeNotSet` → show the D2 copy, and never read the key.
  - There is no `canEvaluatePolicy` pre-check that might skip the gate, and the flow never falls back to `.deviceOwnerAuthenticationWithBiometrics`.
- Test: when the authenticator is injected to return `.passcodeNotSet`, the vault read count is 0 and the D2 copy is shown.

## D3: Copy is allowed, and the clipboard clears after 60 s

- The only write is:
  `UIPasteboard.general.setItems([[UTType.utf8PlainText.identifier: nsec]], options: [.localOnly: true, .expirationDate: Date.now.addingTimeInterval(60)])`.
- Nothing ever sets `UIPasteboard.general.string`, and the flow has no `.textSelection`, `ShareLink` or `UIActivityViewController`. A source check enforces this.
- The r2 `changeCount` guard on hide stays.
- An accepted limitation, already stated in the copy: for 60 s, any keyboard with full access, or any app the person pastes into, can read the key. iOS shows its paste prompt for reads from other apps, but not for keyboards.

## D4: an app-level Face ID check with passcode fallback, no lock on the stored key itself

- The stored key does not change:
  - The primary item stays `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and not synchronizable (`KeyVault.swift:57`).
  - The backup item stays `kSecAttrAccessibleWhenUnlocked` and synchronizable (`KeyVault.swift:156`).
- No `SecAccessControl` and no `.userPresence` are added to either item. The PR must not touch `KeyVault`'s write paths.
- S5 has to stay explicit in the copy and the doc. The check stops someone who is casually holding an unlocked phone. It does not stop:
  - someone who knows the passcode
  - code running inside the app process
  - a device signed in to the same Apple Account, which already receives the key through the iCloud backup item
- That is the accepted v1 tradeoff, and Seth made the call (D4). It isn't an open question.

## D5: no second disclosure for an account with verified, recorded consent

"Verified, recorded consent" in code means:

1. **Recorded.** The journal store (SwiftData, on this iPhone) contains a `JournalFlag` row whose `name` is exactly `"publishDisclosureAccepted|" + <active owner's pubkey, 64-character lowercase hex>`, from `PublishDisclosure.flagName(owner:)`.
2. **Recorded by the person.** The only way that row gets written is `PublishDisclosure.accept()`. Its only caller is `acceptDisclosure()`, which is the sheet's **Continue** button (`GratefulDayApp.swift:77`). **Not now** writes nothing. Save-triggered publishing (R1) must never write it.
3. **Verified.** It is checked with `PublishDisclosure(context:owner:).isAccepted()` for the *active* owner at publish time (`SyncService.swift:139-140`). The flag doesn't carry over between accounts. A flag without the `|<pubkey>` suffix (`JournalFlag.publishDisclosureAccepted` alone) does **not** count.
4. **What doesn't count:** anything in UserDefaults or `AppStorage`, a relay event, an iCloud backup, or a flag under a different pubkey. A reinstall deletes the store, so it asks again. That is correct.

**Requirements for the save-sync PR (#21, and any r3 copy PR):**
- When the flag is present, the new spec A line and the Learn more line never trigger a sheet.
- When it's absent, the sheet appears only at its existing entry points (R1).

**Tests:**
- With the flag present for owner A, a save publishes and no sheet appears.
- With the flag present for owner A only, owner B gets the sheet, and B's save stays local.
- The unscoped legacy name doesn't count as consent.
- No code path other than `accept()` inserts the name. This is a source check.

## What I couldn't settle (for Seth)

- **Consent isn't versioned.** The flag records *that* the person accepted, not *which wording* they saw. Because of D5, Seth's existing acceptance covers the pre-r3 sheet, which didn't say that later writing is backed up automatically. That is the product decision Seth made, and it isn't a security defect.
- **Consequence:** if a later sheet change needs everyone to accept again, the app can't tell old acceptances from new ones. It would need a new flag name, which means a migration-free rename such as `publishDisclosureAccepted.v2|<pubkey>`.
- **My recommendation:** don't add versioning now. Record that limitation in the doc so a future re-consent decision starts from it.

Nothing else is open on the security side. Once Prep's r3 contains everything above, I sign off the security section.
