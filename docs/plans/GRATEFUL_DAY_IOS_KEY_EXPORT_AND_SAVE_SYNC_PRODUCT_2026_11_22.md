---
title: "Grateful Day iOS — Show Journal Key (export) design, and save-triggered publishing product rules"
tags: [grateful-day, ios, keys, export, privacy, sync, design]
status: active
created: 2026-11-22
updated: 2026-11-23
---

**Author:** Prep. **Security review:** Audit gave PASS with tightenings on 2026-11-22 (event 81db6999); they're folded into §1.6 as r2. **Decision:** Seth.
**Status:** **r3, Audit security sign-off complete (§1.6, §2.4.1; 2026-11-23, events 7e326515, 9cc39f05). Awaiting Seth's confirmation.** r3 records Seth's D1–D5 rulings (2026-11-23, event a30708b0; logged by Chief as P49). **Nothing in Part 1 may be built until Seth confirms r3** (Chief, event a69261d8). Audit signs off §1.6 and §2.4.1.

## r3 changes (2026-11-23)

| | Seth's ruling | What r3 changes |
|---|---|---|
| D1 | Approved in principle, pending the final design and security requirements | §1.3–1.7 are the final design. No behaviour was added or removed from r2. |
| D2 | Device passcode required | Already in §1.4 Screen 2 and the r2 D2 note. Now a requirement, not a recommendation. |
| D3 | Copy allowed, 60 s clipboard expiry | Already S3/S3+. Now a requirement. |
| D4 | App-level biometric check with passcode fallback; no lock on the stored key | Already S5. Item-level access control is now **out of scope**, not deferred. |
| D5 | No second disclosure for an account with verified, recorded consent | New §2.4.1 defines "verified, recorded" against the code. |

**Grounding re-checked on `origin/main` 2a424a2** (after #19) and `origin/phase1/save-triggered-sync` (#21): `PublishDisclosure.swift`, `GratefulDayApp.swift` (`acceptDisclosure`), `Storage/JournalRepository.swift` (`flag`/`setFlag`/`publishingAccepted`), `Storage/JournalStore.swift` (`removeAllData`).
**Grounded in:** `origin/main` 36924e3: `Account/KeyVault.swift`, `Account/AccountCopy.swift`, `PublishDisclosure.swift`, `TodayEditorModel.swift`; the key design (`PLANS/GRATEFUL_DAY_IOS_KEY_STORAGE_BACKUP_DESIGN_2026_11_21.md` §2, option B: "Later, advanced only, with its own review"); the M5 flows doc term rules.

---

# Part 1 — Show journal key (export the nsec)

## 1.1 Problem

People can bring a Nostr key in (F5, "Use my Nostr account"), but a key Grateful Day creates can't leave the app. That contradicts Nostr's main promise to the user: you own your identity. The iCloud backup only helps someone who stays in Grateful Day on Apple devices.

**Who needs it:** a small, deliberate group, such as people who want to read their journal on the web or use the same account in another Nostr app. Most people should never see this screen. That decides most of the design: **put it out of the way, make it slow on purpose, and keep it plain.**

**One-sentence version:** *In Settings → Account, someone who has authenticated with Face ID or their passcode can see and copy their journal key, so they can use the same account in another Nostr app.*

## 1.2 What we deliberately leave out (v1)

| Left out | Why |
|---|---|
| QR code | It's easy to photograph from across a room, and it adds a second presentation to secure. Reconsider if people moving to a desktop app ask for it. |
| Share sheet, file export, AirDrop | The key would end up in Messages, Mail, iCloud Drive or another app's storage, where we can't reach it. |
| Password-encrypted export (NIP-49 `ncryptsec`) | It's a new crypto surface (rule: no encryption changes without approval), and not every client supports it. Possible Phase 2 item. |
| Item-level Keychain access control (`.userPresence` on the stored key) | That's a change to the key storage architecture. See Decision D4. |
| Remembering authentication across visits | Each visit asks again. |

## 1.3 Where it lives

Settings → Account, in a separate section **below** the backup and sign-out rows:

- Section header: **Advanced**
- Row: **Use your journal key in another app**
- Shown only when the account is connected **and** the key is readable on this iPhone. If the account is signed out, the key is missing or there's a mismatch (F6), the row is hidden and the existing F6 copy applies.
- It is never offered in onboarding, prompts, banners or the disclosure sheet.

## 1.4 Flow (3 screens, each one with a way back)

**Screen 1: Before you continue** (pushed onto the Settings navigation stack)

> **Your journal key is your account**
>
> Your journal key is your Nostr secret key (nsec). Paste it into another Nostr app to use the same account there.
>
> Anyone who has it can read all your private reflections, including earlier versions, and save to your account as you. This can't be undone by changing a password. There isn't one.
>
> - Only paste it into an app you trust.
> - Never send it in a message or email, or post it.
> - Grateful Day will never ask you for it.
>
> [**Show journal key**] (primary) [**Cancel**]

**Screen 2: Device authentication** (system UI)
- Uses `LAContext` with `.deviceOwnerAuthentication`: Face ID or Touch ID, falling back to the device passcode.
- Reason string (`localizedReason`, plus `NSFaceIDUsageDescription` in Info.plist): **"Confirm it's you to show your journal key."**
- **Cancelled or failed:** go back to Screen 1 quietly, with no error banner. Nothing is shown.
- **No passcode set** (`.passcodeNotSet`): don't show the key. Copy: **"To show your journal key, set a passcode for this iPhone in Settings → Face ID & Passcode."** (Decision D2.)
- **Biometrics locked out:** the passcode fallback handles it. No extra UI.

**Screen 3: Your journal key**
- The account line first: **"Account"** plus the npub shortened (`npub1abcd…wxyz`), so the person can check it matches the other app.
- The key starts **hidden** as a row of dots. The button **[Show]** reveals it and toggles to **[Hide]**.
- When shown: monospaced, in groups of 4 characters, wrapping at every Dynamic Type size, **not selectable**. Copying goes through the button only, so the expiry rule below always applies.
- **[Copy journal key]**:
  - Writes to the pasteboard **local only** (no Universal Clipboard, so it never reaches the Mac) and with an **expiry of 60 seconds**.
  - Confirmation, using a standard accessibility announcement: **"Copied. It will be cleared from the clipboard in 1 minute. Paste it now."** The copy doesn't claim the clipboard is private: a keyboard app with full access can read it during that minute (Audit S3).
  - Copying doesn't require the key to be shown first, so someone can copy without the key ever being on screen. That's the safest path, and it's the one we recommend.
- Footer: **"Done"** pops back to Settings → Account.

**Hiding again (required):**
- When the person leaves the screen, the app leaves the foreground (any `scenePhase` other than `.active`, including the app switcher), or **2 minutes** pass, the key is hidden **and the screen pops back to Screen 1**. Seeing it again needs a new authentication.
- **App-switcher snapshot:** while the app isn't active, a plain cover replaces the screen so the system snapshot never contains the key.
- **Screen recording or mirroring** (`UIScreen.isCaptured`, or the scene equivalent): the key shows dots and [Show] is disabled, with **"Your screen is being recorded or shared, so your key is hidden."** Copy still works.
- **Screenshot taken while the key is shown** (`userDidTakeScreenshotNotification`; iOS can't block screenshots): a non-blocking notice, **"Your screenshot includes your journal key. Delete it from Photos, and from Recently Deleted."**

## 1.5 Accessibility

- VoiceOver: while hidden, the key element reads **"Journal key, hidden"**. Once shown, it reads character by character, by group, and only when focused. It's never part of a combined element or an automatic announcement.
- Screen 3 says once, in its header hint: **"VoiceOver reads your key aloud. Use headphones if others are nearby."**
- Every button is at least 44 pt. The flow works at the largest accessibility text size with no truncation, and the key wraps instead of scrolling sideways.
- Contrast and colours follow the existing design system. Warnings use text, not colour alone.

## 1.6 Security requirements (for Audit to confirm or tighten)

1. **S1.** The key is read from the Keychain **only after** authentication succeeds, and only when Screen 3 appears. It's never preloaded.
2. **S2.** The key string is never written to logs, analytics, crash reports, `SceneStorage`/`AppStorage`, state restoration, UserDefaults, SwiftData or temporary files. Its lifetime in memory ends when the screen hides it (best effort: drop references, and don't keep it in long-lived view models).
3. **S3.** Pasteboard writes are `localOnly: true` with a 60-second `expirationDate`. Nothing else writes the key to the pasteboard.
4. **S4.** No network request or relay call is made from this flow.
5. **S5.** The authentication is an app-level gate. It is **not** cryptographic protection: anyone who has the unlocked phone and its passcode can pass it, just as they could reach the rest of the phone. The copy doesn't claim more than that.
6. **S6.** The F5 rule changes to: "nsec" may appear **only** on the F5 import screen and on Screen 1. Everywhere else it stays "journal key".
7. **S7.** Tests, described as behaviour:
   - With no authentication, no key is read and none is rendered.
   - A cancelled or failed authentication shows nothing.
   - Backgrounding hides the key and needs a new authentication.
   - The 2-minute timeout hides it.
   - While the screen is captured, the key isn't rendered.
   - The pasteboard item is local only and has an expiry.
   - The row is hidden when signed out, when the key is missing and on a mismatch.
   - The exported nsec decodes back to the account's pubkey (round trip through `NostrKeys.decodeNsec`).

**Audit tightenings (r2, required):**
- **S1+**
  - Create a fresh `LAContext` for each attempt, with `touchIDAuthenticationAllowableReuseDuration = 0`.
  - Read the key from `readPrimary()` only, never from a backup item.
  - Before Screen 3 renders anything, derive the pubkey from the secret that was read and require it to equal `activeOwner`. This is a runtime check. On a mismatch, show nothing and use the F6 copy.
- **S2+**
  - The key lives only in screen-local `@State`, never in `AccountModel` or the environment.
  - The view is marked `.privacySensitive()`.
- **S3+** When the key hides, the pasteboard is cleared only if `changeCount` still equals our write, so we never wipe something the user copied later.
- **S4+** No new entitlement, dependency or Info.plist key except `NSFaceIDUsageDescription`.
- **D2 implementation:** use the `.passcodeNotSet` error from `.deviceOwnerAuthentication` as the gate, with no separate check.
- **S7+ tests**
  - The authenticator is injected, and the vault read count is 0 until it succeeds.
  - A pubkey mismatch renders nothing.
  - The pasteboard `changeCount` guard works.
  - `.inactive` hides the key and pops back to Screen 1. Checking `.background` alone isn't enough.
  - A source check confirms no SyncLog, StorageLog or `Logger` call takes a key or nsec parameter.
- **Context for Seth (Audit):** the iCloud backup already lets any device signed in to the same Apple Account hold the key. Export doesn't widen *who* can hold it. It widens *which apps* can.

**r3 requirements from Seth's rulings (Audit, `RESEARCH/GRATEFUL_DAY_IOS_KEY_EXPORT_R3_SECURITY_SIGNOFF_2026_11_23.md`, against `main` 2a424a2).** S1–S7 and the r2 tightenings all still apply. None of these loosens them.
- **D2 (passcode required)**
  - The only gate is `LAContext().evaluatePolicy(.deviceOwnerAuthentication, …)`.
  - On `LAError.passcodeNotSet`, show the D2 copy and never read the key.
  - No `canEvaluatePolicy` pre-check that could skip the gate, and no fallback to `.deviceOwnerAuthenticationWithBiometrics`.
  - Test: with the injected authenticator returning `.passcodeNotSet`, the vault read count is 0 and the D2 copy is shown.
- **D3 (Copy, 60 s)**
  - The only pasteboard write is `UIPasteboard.general.setItems([[UTType.utf8PlainText.identifier: nsec]], options: [.localOnly: true, .expirationDate: Date.now.addingTimeInterval(60)])`.
  - Nothing sets `UIPasteboard.general.string =`. The flow has no `.textSelection`, `ShareLink` or `UIActivityViewController`. A source check enforces both.
  - The r2 `changeCount` guard on hide stays.
- **D4 (app-level check, stored key unchanged)**
  - The primary item stays `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and not synchronizable (`KeyVault.swift:57`).
  - The backup item stays `kSecAttrAccessibleWhenUnlocked` and synchronizable (`KeyVault.swift:156`).
  - No `SecAccessControl` or `.userPresence` on either item. **The export PR must not touch `KeyVault`'s write paths.**
  - S5 stays explicit in the copy and this doc. The check stops someone casually holding an unlocked phone. It does **not** stop:
    - someone who knows the passcode
    - code running inside the app process
    - a device on the same Apple Account, which already gets the key through the iCloud backup item

## 1.7 Acceptance criteria (for when it's approved)

- [ ] The row appears only under Settings → Account → Advanced, only when connected and the key is present.
- [ ] Screen 1 copy matches §1.4 word for word. No path skips Screen 1 or authentication.
- [ ] The key isn't visible until [Show] after a successful authentication. Copying works without showing it.
- [ ] The copied text pasted into another Nostr client logs into the same npub that Grateful Day shows (device check, plus web decryption once that's verified).
- [ ] The clipboard is empty after 60 seconds, and the key never appears on a nearby Mac's clipboard.
- [ ] Backgrounding, the app switcher, leaving the screen and the 2-minute timeout each hide it and require authenticating again.
- [ ] A screen recording shows dots. A screenshot triggers the notice.
- [ ] VoiceOver and the largest text size work end to end (SHIP's accessibility checklist).
- [ ] S1–S7, including the r2 tightenings, pass Audit review of the implementation PR.

## 1.8 Decisions (Seth, 2026-11-23, event a30708b0)

- **D1. Design approved in principle.** §1.3–1.7 as written in r3 are the design Seth is asked to confirm. QR, share and file export stay out of v1.
- **D2. A device passcode is required** to show or copy the key. Gate: the `.passcodeNotSet` error from `.deviceOwnerAuthentication`, with the §1.4 copy. People without a passcode keep their account through the iCloud backup.
- **D3. Copy is allowed**, local only, with a 60-second expiry (S3, S3+).
- **D4. App-level authentication**: Face ID or Touch ID with passcode fallback (`.deviceOwnerAuthentication`). The stored Keychain item gets **no** access-control change, so automatic publishing keeps signing without a prompt. Changing that needs a new decision and Audit review.

## 1.9 Security tradeoffs Seth's rulings accept

Audit confirms 1–3 are settled by D2–D4, not open questions. Item 4 is the one limitation Audit couldn't settle on Seth's behalf. All four are listed so Seth's confirmation of r3 covers them explicitly.

1. **The passcode is the whole gate (D4/S5).** Anyone who knows the phone's passcode can export the key. Face ID adds nothing against them, because the fallback is the passcode. On the phone itself that person can already read the journal, but **export lets them take the key off the phone and read every private reflection, including earlier versions, from anywhere, permanently.** There's no rotation for a Nostr key. *Prep: accept for v1.* The alternative (item-level `.userPresence`) would prompt on every publish, which Seth ruled out.
2. **Clipboard exposure for 60 s (D3).** These are iOS's documented paste rules (Audit, from documentation, not tested on a device):
   - **Other apps:** since iOS 16, an app that reads the pasteboard in code triggers an Allow prompt. The per-app setting "Paste from Other Apps" can be Ask, Deny or Allow. There's no prompt when the person pastes themselves (edit-menu Paste, keyboard paste, `UIPasteControl`), or for an app already set to Allow. In practice the exposure is any app set to Allow, plus the app they choose to paste into.
   - **Keyboards:** a third-party keyboard with Full Access can read the general pasteboard. Apple's documentation doesn't say whether it gets the prompt, so treat it as able to read the key silently for those 60 s. The built-in keyboard isn't a risk.
   - **Pattern detection** (`detectPatterns`) runs without a prompt, but it only reports types such as URL or number. It can't read the nsec.
   - **Universal Clipboard** is blocked by `.localOnly`, so the key never reaches a nearby Mac.
   
   *Prep and Audit: accept.* The copy doesn't call the clipboard private, and copy-without-show stays the recommended path.
3. **Screenshots can't be blocked.** iOS only tells us afterwards. The notice is the mitigation. *Prep: accept.*
4. **Consent isn't versioned (D5).** An existing acceptance covers the pre-r3 sheet wording, and a future re-consent would need a new flag name. Details in §2.4.1. *Prep and Audit: don't add versioning now.*


---

# Part 2 — Save-triggered publishing: product rules and wording (Sous, Priority A)

## 2.1 The fact that shapes this

The editor saves locally **every 0.5 s** after typing pauses (`TodayEditorModel.saveDelay`). Each publish is a new 36669 version with a **public timestamp** ("When you saved each reflection, and each time you edited it" is already in Learn more), and every earlier version stays readable by the key forever ("including earlier versions"). If the publish trigger follows local saves closely, one sitting becomes dozens of public edit times and archived versions. **The trigger has to follow writing sessions, not keystrokes.**

## 2.2 Product requirements

1. **R1. Consent first.** A save never publishes for an account that hasn't accepted spec A on this iPhone. A save **never opens the disclosure sheet**, either: the sheet appears only at its existing entry points, never over the editor mid-sentence. Until it's accepted, saves stay local, as they do today.
2. **R2. One sitting, one publish.** A pass starts when the person has **stopped typing for about 30 seconds**, or right away when they leave Today or the app becomes inactive (where foreground time allows). Sous picks the exact value; **it must not be under 15 s**. Typing again restarts the wait.
3. **R3. No new UI.** No toast, no "Published" message and no new indicator. The existing Saving mark and the synced state are the whole surface. The Saving mark **must not flicker** with each local save during the wait. Visual check: type for one minute, then stop. The mark changes at most twice.
4. **R4. Offline, failures and relays behave as already specified.** No alerts for normal outages, the same retry rules, the same two-relay acknowledgment, fetch-before-publish, and conflicts going to M6 review. Nothing in Part 2 changes those rules.
5. **R5. Unsynced text is never lost or hidden.** The text is on disk before any pass. An interrupted pass leaves the entry in Saving, never in synced.

## 2.3 Wording

The current sheet tells people that their existing reflections will be backed up ("N reflections will be backed up to your account"). **It doesn't say that what they write later goes up on its own.** With save-triggered publishing, that becomes the normal behaviour, so the sheet should say so.

- **Spec A sheet: add one line** after the count line (or in its place when the count is 0):
  > **"After this, what you write is backed up to your account automatically."**
- **Learn more, under "Can be seen by others"**: add after the bullets (only once R2 ships):
  > **"Grateful Day backs up a reflection a little while after you stop writing, so one sitting usually shows as one edit."**
- **Already accepted** (Seth's device): **no new prompt**. Continue already allowed publishing, and only the timing changes. The new line applies to sheets shown from now on. *If Seth wants everyone to see it, that's a one-time re-show, and it's his call (D5).*
- These lines become part of the flows doc and `DisclosureCopy` together, in the same PR as the save-trigger work.

## 2.4 Decision (Seth, 2026-11-23)

- **D5. No second disclosure** for an account whose consent is verified and recorded (definition below). The new §2.3 sheet line only reaches people who see the sheet from now on.

### 2.4.1 What "verified, recorded consent" means in code

An account has verified, recorded consent **on this iPhone** when, and only when, all of these hold:

1. **Recorded.** The journal store (SwiftData, on this iPhone) contains a `JournalFlag` whose `name` is exactly `PublishDisclosure.flagName(owner:)`, i.e. `"publishDisclosureAccepted|" + <active owner's pubkey, 64-character lowercase hex>`. Its `setAt` is when they tapped Continue.
2. **Recorded by the person.** Only `PublishDisclosure.accept()` writes that row. Its only production caller is `acceptDisclosure()`, the sheet's **Continue** button (`GratefulDayApp.swift:77`), for the `activeOwner` at that moment. **Not now**, swiping the sheet away, a migration, a restore, an import, a sync pass and save-triggered publishing (R1) never write it. On `main` 2a424a2 this already holds.
3. **Verified.** At publish time it's checked with `PublishDisclosure(context:owner:).isAccepted()` for the *active* owner (`SyncService.swift:139-140`; `JournalRepository.publishingAccepted` uses the same name for the Saving mark). Consent doesn't carry over between accounts. A bare `publishDisclosureAccepted` without the `|<pubkey>` suffix (the unscoped legacy name) is **not** consent.
4. **What doesn't count:** anything in UserDefaults or `AppStorage`, a relay event, an iCloud backup, or a flag under a different pubkey. A new iPhone, a reinstall or "Remove account and local data" (`JournalStore.removeAllData()` deletes the store) leaves no flag, so the sheet is shown again. That's intended.

**Requirements for the save-sync PR (#21, and any PR that ships the §2.3 copy):**
- When the flag is present, the new spec A line and the Learn more line never trigger a sheet.
- When it's absent, the sheet appears only at its existing entry points (R1).

**Required tests:**
- With the flag present for owner A, a save publishes and no sheet appears.
- With the flag present for owner A only, owner B gets the sheet at its existing entry point, and B's save stays local.
- The unscoped legacy name doesn't count as consent.
- Not now leaves no flag, and after `removeAllData()` the flag is gone.
- Source check: no code path other than `accept()` inserts the name, and `accept()` has exactly one non-test caller.

**Known limitation, open for Seth: consent isn't versioned** (Audit, Prep agree).
- The flag records *that* the person accepted, not *which wording* they saw. Under D5, an existing acceptance covers the pre-r3 sheet, which didn't say that later writing is backed up automatically. That's Seth's product call, not a security defect.
- Consequence: if a future sheet change needs everyone to accept again, the app can't tell old acceptances from new ones. That would need a new flag name, such as `publishDisclosureAccepted.v2|<pubkey>`, which needs no migration.
- **Recommendation (Prep and Audit): don't add versioning now.** A future re-consent decision starts from this note.

## 2.5 What Prep checks on the draft PR

- R1–R5 are covered by tests or a visual check.
- The two copy lines match §2.3 word for word.
- The minimum wait is ≥ 15 s.
- A save never opens the sheet.

---

# Part 1 — Final UX and security copy (Prep, 2026-11-25, against iOS `origin/main` 10ae4d6)

Seth asked for this in the #general Phase 1 handoff (event 5f1caa72, §6). I checked the r3 design against `Account/AccountView.swift` and `Account/AccountCopy.swift` on 10ae4d6. Nothing on main implements export yet: there's no `LocalAuthentication` and no `NSFaceIDUsageDescription`.

## Copy-only corrections to §1.4 (no behaviour change)

1. **Screen 1, third bullet.** "Grateful Day will never ask you for it." is wrong, because the F5 import screen does ask for the nsec. It becomes **"No one from Grateful Day will ever ask you for it."**
2. **D2 no-passcode copy.** "Settings → Face ID & Passcode" is wrong on Touch ID iPhones. It becomes **"To show your journal key, turn on a passcode for this iPhone in Settings."**
3. **Strings r3 didn't name.** They're fixed here so Sous doesn't have to invent them (below).

## Final strings (add to `AccountCopy` as a new `// Export` group)

| Where | String |
|---|---|
| Section header (connected, key readable) | Advanced |
| Row | Use your journal key in another app |
| Screen 1 and Screen 3 nav title | Journal key |
| Screen 1 heading | Your journal key is your account |
| Screen 1 body ¶1 | Your journal key is your Nostr secret key (nsec). Paste it into another Nostr app to use the same account there. |
| Screen 1 body ¶2 | Anyone who has it can read all your private reflections, including earlier versions, and save to your account as you. This can't be undone by changing a password. There isn't one. |
| Bullet 1 | Only paste it into an app you trust. |
| Bullet 2 | Never send it in a message or email, or post it. |
| Bullet 3 | No one from Grateful Day will ever ask you for it. |
| Primary / secondary | Show journal key / Cancel |
| `localizedReason` and `NSFaceIDUsageDescription` | Confirm it's you to show your journal key. |
| No passcode (D2) | To show your journal key, turn on a passcode for this iPhone in Settings. |
| Screen 3 account line | Account · `npub1abcd…wxyz` (existing `shortNpub`) |
| Toggle | Show / Hide |
| Copy button | Copy journal key |
| Copied (announcement and inline) | Copied. It will be cleared from the clipboard in 1 minute. Paste it now. |
| Captured screen | Your screen is being recorded or shared, so your key is hidden. |
| Screenshot notice | Your screenshot includes your journal key. Delete it from Photos, and from Recently Deleted. |
| VoiceOver, hidden | Journal key, hidden |
| VoiceOver header hint | VoiceOver reads your key aloud. Use headphones if others are nearby. |
| Footer | Done |

**Placement on main:** a new `Section` in the `.connected` case, after the account/backup/sign-out section and its status sections, and above the destructive "Remove account and local data" section. It's hidden in every other state (`.guest`, `.signedOut`, `.keyMissing`, `.mismatch`, `.unknown`, `.locked`, `.keyUnavailable`).

**S6 term rule:** "nsec" now appears in exactly two places, the F5 `importPrompt` and Screen 1 ¶1. The `AccountCopy` header comment ("nsec appears only on the import screen") changes with it.

## One open design conflict, for Audit and then Seth: clear-on-hide breaks the copy path

- The r2 rule S3+ clears the pasteboard "when the key hides" if `changeCount` still matches.
- §1.4 hides the key whenever `scenePhase` isn't `.active`.
- Together they cause this: the person taps **Copy journal key** and switches to the other Nostr app. Grateful Day goes `.inactive`, hides the key and clears the clipboard, so **there's nothing left to paste**. The main use case fails, and it contradicts the "Paste it now" copy.
- **Prep recommendation:** remove clear-on-hide. The 60 s `expirationDate` (D3) is the only clearing mechanism. That's within D3 and Seth's §6 brief ("clipboard expiry … without overwriting newer clipboard contents"), and it never touches anything copied later. Every other hide rule stays as written.
- Fallback if Audit wants an early clear: clear only on the 2-minute timeout. That's already moot, though, because the expiry has passed by then.
- This loosens an Audit r2 tightening, so it needs Audit's verdict before Chief lists it as decided.

**E1 status (2026-11-25):**
- **Audit accepts** dropping clear-on-hide (event d562846e). The pasteboard is written only by the D3 `setItems` call. Hiding, the timeout, Done, back, sign-out and backgrounding never write to or clear it.
- **Test change:** the S7+ "`changeCount` guard" test is replaced by a test that hiding, `.inactive` and the timeout leave the pasteboard unchanged.
- **Signed off:** Audit has signed off the export security section, including both copy fixes.
- **Approved:** Chief approved the copy fixes (event 10ae8238).
- **Still open:** E1 goes to Seth in Chief's consolidated update.
