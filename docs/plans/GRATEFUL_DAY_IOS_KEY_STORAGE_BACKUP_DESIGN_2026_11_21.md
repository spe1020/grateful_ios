---
title: "Grateful Day iOS — Key Storage and Key Backup Design (MVP item 8, M5 gate)"
tags: [grateful-day, ios, keys, keychain, backup, m5, design]
status: active
created: 2026-11-21
---

> **Approved by Seth with changes (2026-11-21, event 43dbe869). r3 below reflects his decisions; §6 changed most.** M5 is authorized on this basis. No release or deployment.

**Author:** Sous. **Co-reviewer:** Audit (notes: `RESEARCH/GRATEFUL_DAY_IOS_KEY_DESIGN_COREVIEW_2026_11_21.md`). **Decision:** Seth.
- Keys, private-key management, recovery and licensing questions need his explicit approval.
- No M5 code starts before he approves.

**Inputs:**
- `PLANS/GRATEFUL_DAY_IOS_STORAGE_BACKUP_RECOMMENDATION_2026_11_21.md` §4–5, including Audit's S3.
- `PLANS/GRATEFUL_DAY_IOS_MVP_RECOMMENDATION_2026_11_21.md`: item 8, spec A and spec B.
- `PLANS/GRATEFUL_DAY_36669_30078_INTEROP_SPEC_2026_11_21.md`.
- `PLANS/GRATEFUL_DAY_IOS_PROVENANCE_INVENTORY_2026_11_21.md`.
- The iCloud Keychain backup in Seth's Zap Cooking iOS app (Wisp lineage), as a reference design.

**Seth's standing rules:**
- No unreviewed backup or recovery mechanism.
- No new privacy guarantee without his approval.
- A failed read is never "empty".

## 1. Recommendation in one paragraph

The journal key lives in this iPhone's Keychain only: `WhenUnlockedThisDeviceOnly`, never synced.

For MVP item 8:
- When someone creates a journal key, the app offers to **keep a backup copy of the key in iCloud Keychain**. The person must make a **clear affirmative choice**; nothing is pre-selected, and declining is equally easy (Seth). That's a separate synced Keychain item, which Apple encrypts end to end across the person's Apple devices.
- On a new iPhone, the person chooses **"I've used Grateful Day before"**. The app finds the backup, restores the key, then runs spec B's fetch-first connect.

**Extra secret (§9.1), Seth's decision: no PIN (option c)** for the first implementation.
- Background on the team recommendation: A 6-digit PIN doesn't stop anyone who has the backup (§11), and it adds the risk of a forgotten PIN.
- A long recovery code would give real protection, but it asks people to store a secret, which is what item 8 is meant to avoid.

**Implementation:** write it fresh from this spec on Phase 0's NIP-44 and CommonCrypto, rather than adapting Wisp's files (§9.5). Nothing here touches Nostr.

## 2. Options considered

| Option | Item 8: one step, no key knowledge | What actually protects the backup | New interop contract? | Verdict |
|---|---|---|---|---|
| **A. Backup copy in iCloud Keychain** (variants in §9.1: (a) recovery code, (b) 6-digit PIN, (c) no extra secret) | Yes for (b) and (c). (a) asks the person to keep a code | iCloud Keychain's end-to-end encryption. Only (a) adds real offline strength | No | **Recommended**, with variant (c) |
| B. Show or export the secret key (nsec) | No. The person has to understand and store a key, and "nsec" is banned in guest-visible copy | Whatever the person does with it | No | Later, advanced only, with its own review |
| C. Password-encrypted key on relays (NIP-49 in a 30078 event) | Restore needs the npub *and* a password | Password strength only. The ciphertext is public forever | **Yes** | Not for MVP |
| D. No backup | — | — | No | Fails item 8 |

## 3. Storage: location and access class (Audit bar 1)

**Primary key (used for signing):**
- Keychain `kSecClassGenericPassword`, service `app.gratefulday.ios.journal-key`, account `primary`. The value is the 32-byte secret.
- `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, `kSecAttrSynchronizable = false`. That means:
  - not readable while the phone is locked
  - not in iCloud Keychain
  - not restorable to another device from any backup
- No biometric gate in MVP.
- **Never** in UserDefaults, SwiftData, logs, crash reports, the pasteboard or analytics.

**Backup item (opt-in):**
- Service `app.gratefulday.ios.journal-key-backup`, account `bk_<random UUID>`. The name is opaque, so it doesn't reveal the npub.
- `kSecAttrSynchronizable = true`.
- **`kSecAttrAccessibleWhenUnlocked`**: synced items need a non-`ThisDeviceOnly` class, but not `AfterFirstUnlock`. The backup is only read during an unlocked, foreground restore, so it takes the stricter class (Audit item 6).
- Value: `{ "v": 1, "kind": "plain" | "pin" | "code", … }`.
  - (c) stores the 32-byte key, base64-encoded.
  - (a) and (b) store `salt` (16 random bytes) and `ct`. The key is `PBKDF2-HMAC-SHA256(secret, salt ‖ "gratefulday-icloud-key-backup", 600_000)`, used as the NIP-44 v2 conversation key via Phase 0's `NIP44.encrypt(_:conversationKey:)`.

**Connected-account marker:**
- A non-secret row in the journal store recording the connected pubkey.
- It stays out of device backups like the journal.
- It's how the app tells "a key should be here" apart from "never connected" (§7).

## 4. What stays out of backups (Audit bar 2)

| Data | iCloud / Finder device backup | iCloud Keychain sync | On a new iPhone |
|---|---|---|---|
| Journal store (reflections, marker) | Excluded (M2/P10) | — | No |
| Primary key | `ThisDeviceOnly`. An encrypted Finder backup restores it only to the *same* device **[verify]** | No | No |
| Backup item (if chosen) | Synced items aren't device-backup data **[verify]** | Yes, end to end encrypted, **only if the person has iCloud Keychain (Passwords & Keychain) sync on** | Yes, once sync delivers it |
| UserDefaults | Backed up: only onboarding and reminder flags. **No key material, pubkey or counts** | — | Yes |

## 5. New iPhone, lost device, reinstall (Audit bar 3)

**First launch on any iPhone:**
- The start screen offers **"I've used Grateful Day before"** next to starting fresh (Audit item 3).
- Choosing it searches for a backup.
  - **Found:** restore. The PIN or code is asked for only under variants (a)/(b). Then spec B's fetch-first connect runs.
  - **Not found yet:** "Your backup hasn't arrived from iCloud yet. Make sure iCloud Keychain is on in Settings, then try again." The app re-checks on each later launch and foreground until the person dismisses it.
  - **It never offers to create a new key from this screen.**
- **Using an existing Nostr identity:** "Use my Nostr account" imports an existing key (spec B), stored exactly like a created key. External signers (NIP-46) stay out of scope until separately approved (spec A: the app controls the signer).
- The app checks for an existing identity (Keychain key, marker, iCloud backup) **before** offering to create one. A delayed or failed restore never leads to a silently generated replacement (Seth).
- **Creating a key** always needs an explicit confirmation with consequence copy: "This makes a new journal key. Reflections written with a different key won't open with this one."

| Situation | With a backup | Without a backup |
|---|---|---|
| New or replacement iPhone, same Apple account, iCloud Keychain on | Restore as above. Unsynced reflections from the old phone are lost | The key is gone. Synced private reflections stay on relays but can't be read. **The decline copy must say this** |
| iCloud Keychain sync off | The backup item exists only on the old phone. It never syncs | — |
| App deleted and reinstalled, same phone | The primary Keychain item usually survives (S3). Key present, no marker → treat as connected, fetch first, never a second key | Same |
| Forgotten PIN or code (variants a/b only) | Not recoverable. If the key is still on a device, the person makes a new backup | — |

**Detecting iCloud Keychain** (Audit item 2):
- The app can't tell whether Passwords & Keychain sync is on. `ubiquityIdentityToken` only shows that the person is signed in to iCloud.
- A successful write of the backup item is **never** shown as "backed up". The confirmation reads: "Backup saved. It reaches your other devices if iCloud Keychain is on (Settings → your name → iCloud → Passwords & Keychain)."
- Only the device check proves sync.

**Wrong secret** (variants a/b): after 5 failures, a growing delay, stored in the journal store.

## 6. Sign-out and removing data (Audit bar 4; changed by Seth)

Two separate actions. Neither runs without a clear confirmation, and Audit verifies the ordering and failure handling.

**A. Sign out (keeps the journal):**
1. Confirm. The sheet says what happens: the key is removed from this iPhone; reflections stay on this iPhone; unsynced reflections can't sync until the same account is connected again. **If sync state can't be read, every local reflection counts as unsynced** in the count shown (Audit item 5). **If no iCloud backup exists, a separate warning** (not merged with the unsynced count) says that synced private reflections can't be read again without the key, unless it was kept elsewhere (P16, Audit question 2).
2. Delete the primary Keychain item and **confirm the delete** (`errSecSuccess`, then `errSecItemNotFound` on re-read). If it failed: **stay signed in**, change nothing, show "Couldn't sign out just now." The app never shows "signed out" while the key is still there.
3. Mark the account **signed out** in the journal store (the marker keeps the pubkey with state `signedOut`). If the marker or sync state can't be read, the action is **blocked** before step 2, and every entry counts as unsynced in the warning. The journal stays, readable and writable on this iPhone, and isn't published anywhere. **If this marker write fails after the key delete,** the marker still says `connected` with no key. The next launch shows "Key missing" and offers restore, which is safe and creates no new key. The failure is logged (code only).
4. The iCloud backup isn't touched.

**Account isolation (P15/P16, Audit's proposal):**
- Every entry carries an **owner**: `nil` for a guest entry, or the pubkey it was written or synced under. `JournalEntry.ownerPubkey` is added in M5a as schema V4, an optional field, lightweight migration.
- Connecting an account sets the owner on guest entries only when spec B publishes them under that account.
- On sign-out, owners are kept; entries are **not** turned back into guest entries.
- When account **B** connects: entries owned by **A** are never published, merged or counted as B's guest entries. They stay readable on this iPhone, labelled as belonging to another account. Bringing them into B needs an **explicit choice** by the person. That choice is a later, separately reviewed flow, not in M5.
- When the **same** account (A) reconnects by restore or import, A's entries are picked up again and sync resumes with fetch-first.
- Guest entries (owner `nil`) follow spec B under whichever account connects.
- **What "signed out" blocks:** with the key deleted, nothing can be published or decrypted for that account; writing locally still works (new entries are guest entries).

**Owner and date (Audit r3 co-review, option (a)):** one entry per **(owner, date)**, not per date.
- **Schema V4:** `ownerPubkey: String?` and `entryKey: String?` with `@Attribute(.unique)`, where `entryKey = "<ownerPubkey or guest>|<YYYY-MM-DD>"`. `dateString` stops being unique.
  - `#Unique` needs iOS 18; the app targets 17, so a single unique key property is used instead.
  - Migration V3→V4 is a custom stage: lightweight schema change, then `didMigrate` fills `entryKey = "guest|<date>"` for every existing row. Every pre-M5 row is a guest row. Test: `testV3StoreMigratesToOwnerKeyedEntries`.
- **What Today and the Calendar show:**
  - **Connected as X:** X's rows and guest rows. The editor writes X's row for today if one exists, otherwise the guest row, which becomes X's when spec B publishes it.
  - **Signed out, or never connected:** the editor writes the **guest** row for today. Rows owned by a signed-out account are shown **read-only** with a label ("From your signed-out account"), and the calendar marks those days.
  - A signed-out person writing on a day that A owns therefore creates a separate guest row. A's text is never edited while A is signed out.
- **When B connects (M5b):** fetch-first writes B-owned rows. A row owned by A is never overwritten, merged or published under B.
- **Same date, guest row and owner row:** if X's remote entry and a local guest row exist for the same date, that's spec B's "both, different text" conflict, handled in M6 (Keep both / Set aside), never a silent overwrite.
- **Tests:**
  - `testSignedOutEditOfAOwnedDayCreatesAGuestRowAndLeavesAUntouched`
  - `testBFetchForDateOwnedByANeverOverwrites` (M5b)
  - `testConnectedEditorWritesOwnersRowOtherwiseGuest`
  - `testCalendarShowsSignedOutAccountDaysReadOnly`

**Tests (M5a unit tests; M5b adds the publish-side ones):**
- `testSignOutKeepsJournalAndOwners`: entries stay and keep A's pubkey.
- `testSignOutAThenConnectBPublishesNothingFromA` (M5b, with a fake relay): nothing owned by A is in B's publish queue or on the fake relay.
- `testReconnectingAResumesItsEntries`.
- `testGuestEntriesFollowSpecBUnderB`.
- `testSignOutStaysSignedInWhenKeychainDeleteFails`.
- `testSignOutWarnsAboutUnreadablePrivateEntriesWithoutBackup`.

**B. Remove account and local data (explicit, destructive):**
1. Confirm with consequence copy. If the marker or sync state can't be read, the action is **blocked** (P16). If unsynced reflections exist, name the count: "X reflections are only on this iPhone and will be deleted." Requires a second, deliberate confirmation.
2. Delete the primary Keychain item and confirm the delete; if it fails, stop before touching the journal.
3. Delete the journal store (entries, marker, flags). If that fails, the key is already gone: show "Couldn't remove your reflections. Try again." and retry the delete. Never show "journal couldn't be opened" (untrue) and never create a fresh store over the old file (M2 rule).
4. Separate question: "Also delete the iCloud backup of your key?" Default **No**; deleting it means the identity can't be restored later.

## 6a. Importing an existing key (P14a; Audit co-reviews; flagged to Seth as the part that most needs his eye)

"Use my Nostr account" (spec B) imports an existing secret key. There's no remote signer (NIP-46) in M5 (P14).

- **Entry:** a single secure text field (`SecureField`, autocorrect and spellcheck off). **No `.password` (or any credential) text content type,** because iOS could then offer to save the nsec as a password in iCloud Keychain, outside this design (Audit). Device check G9 confirms there's no save prompt. It accepts `nsec1…` (bech32, Phase 0 `Bech32`) or 64-hex. A "Paste" button reads the pasteboard **once**, on tap only (never on appear), and clears the pasteboard right after reading if `UIPasteboard.changeCount` is unchanged since the read, so it never clears something copied later. Hint copy: "If you copied it on a Mac, it may still be on that Mac's clipboard."
- **Validation:** decode, then check the key with Phase 0's secp256k1 (`Keys`). The person sees the derived **npub**, plus the existing-account check, before saving: "This is the account npub1…". A wrong checksum or invalid key gives "That doesn't look like a Nostr key", and nothing is stored.
- **Never logged** or stored anywhere but the Keychain. The app drops its references to the field value and decoded bytes once saved or cancelled. That's intent, not a guarantee: Swift `String`/`Data` can't be reliably wiped. No analytics or crash breadcrumbs include it. Screenshot redaction for the field is out of scope.
- **Keychain write verified:** write the primary item, read it back, compare the derived pubkey. On mismatch or error, delete what was written, show "Couldn't save the key", and stay in the previous state.
- **Account isolation:** import is a "connect". If the marker says a *different* account is signed out on this iPhone, §6's rules apply: that account's entries stay unpublished and labelled. If it's the same pubkey, entries resume. If a key is already present (connected), import is refused: sign out first.
- **Backup offer:** after import, the same affirmative-choice iCloud backup offer as for a created key (§1).
- **Tests:** `testImportAcceptsNsecAndHex`, `testImportRejectsBadChecksum`, `testImportVerifiesKeychainWriteAndRollsBack`, `testImportRefusedWhileConnected`, `testImportOfSignedOutPubkeyResumesEntries`, `testPasteReadsOnceAndClearsPasteboard`.

## 6b. Delivery split (P13)
- **M5a** (no network code): key storage, create, import (§6a), iCloud backup and restore, both sign-out paths, the §7 states, schema V4 (`ownerPubkey`, marker state).
- **M5b:** connect and sync with spec B fetch-first; the publish-side isolation tests.
- **M6:** conflicts and Set aside. Prep's condition holds: M5 doesn't ship to users without M6.

## 7. A failed key read is never "no key" (Audit bar 5)

Only the first row may lead to onboarding or key creation, and even then only after the §5 confirmation.

| Keychain result | Marker | State | Behaviour |
|---|---|---|---|
| `errSecItemNotFound` | read OK, none | **Guest** | Guest journal; offers "I've used Grateful Day before" first |
| any | **read failed** (store failed, locked or unreadable) | **Unknown** (Audit item 4) | Onboarding, key creation and publishing all blocked. Retry when the store opens |
| `errSecItemNotFound` | present, `connected` | **Key missing** | "Your journal key isn't on this iPhone." Offers restore. **Never a new key.** Publishing blocked |
| `errSecInteractionNotAllowed` | any | **Locked** | Wait for unlock; nothing publishes |
| any other error | any | **Key unavailable** | Logged with the code only; publishing blocked; retry on foreground. Never onboarding or a new key |
| success, pubkey ≠ marker | present, `connected` | **Mismatch** | Publishing blocked; "This iPhone has a different journal key." No automatic fix in MVP |
| success, matches | present or none | **Connected** | With no marker (reinstall), fetch first before anything else |
| success (a newly imported or restored key), pubkey ≠ marker | present, `signedOut` | **Connecting another account** | Allowed (P16). The marker moves to the new pubkey as `connected`; the signed-out account's rows keep their owner and stay read-only and unpublished |
| `errSecItemNotFound` | present, `signedOut` | **Signed out** | Journal usable locally; offers reconnect. The same pubkey resumes its entries; a different account may connect, but entries owned by the signed-out account are never published under it (§6) |

The same rule holds for the backup item: "backup unavailable" is never "no backup". A new backup never overwrites an existing one. Each backup is its own item, and older ones are listed at restore.

## 8. Copy (Prep and Growth; Seth for guarantees)

**To write:**
- the backup offer at key creation
- the decline consequence
- "I've used Grateful Day before"
- "not arrived yet"
- the create-key confirmation
- "Key missing"
- the sign-out warnings
- under (a)/(b): the forgotten-secret warning

**Guarantee wording (Seth):**
- Proposed: "A backup copy of your journal key is kept in iCloud Keychain, which Apple encrypts end to end. Anyone who can sign in to your Apple account on a trusted device could restore it." (Seth: this risk must be explained.)
- It must **not** claim that iCloud Keychain backs up journal entries: only the key is backed up (Seth).
- It must **not** suggest a PIN protects against someone who already has the backup (Audit item 1).
- It must not say Apple can't access iCloud data in general.
- It doesn't go live until device verification passes.

**Banned:** "secret key" and "nsec" anywhere a guest can see. The user-facing term is "journal key" (Prep to confirm).

## 9. Seth's decisions (2026-11-21, event 43dbe869)

| # | Item | Decision |
|---|---|---|
| 9.1 | Extra secret | **No PIN** (option c) for the first implementation, with the risk explained |
| 9.2 | Offer | Offered at key creation; **clear affirmative choice required**; declining allowed |
| 9.3 | New iPhone | "I've used Grateful Day before" first; check for an existing identity before creating one; import of an existing key supported; never a silent replacement |
| 9.4 | Sign-out | **Changed:** ordinary sign-out keeps the journal; a separate "Remove account and local data" deletes it, with clear confirmation (§6) |
| 9.5 | Code | **Fresh, narrowly scoped implementation** on Phase 0; no Wisp backup code copied |
| — | Chief, delegated | **P13** M5a/M5b split (§6b); **P14/P14a** import in, no NIP-46 (§6a); **P15/P16** isolation and sign-out (§6) |
| 9.6 | Messaging | No unverified recovery, backup or security guarantees; real-iPhone testing of Keychain storage, iCloud recovery, account switching, sign-out, backup exclusions and recovery failures before release |

Background for 9.1 (options as presented):

| Option | User cost | Real protection added | Forgotten-secret risk |
|---|---|---|---|
| (a) Recovery code or long passphrase | Must store a code | Strong | High |
| (b) 6-digit PIN | One extra step | Small (all PINs in minutes, §11) | Medium |
| **(c) No extra secret** (chosen) | None | None beyond iCloud Keychain E2E and Apple account security | None |

### 9.5 Code reuse versus writing fresh

**Provenance**, in the Phase 0 inventory method: `gh api repos/barrydeen/wisp-ios/commits?path=…`, then compare blob hashes with `git rev-parse` in `zapcooking_ios`.

| File | Upstream `barrydeen/wisp-ios` commits | Authors upstream | Zap Cooking copy | Barry-only? |
|---|---|---|---|---|
| `BackupCrypto.swift` (104 lines) | `a06548b` (2026-05-21), `e6d8ec2`, `e9981c4` (2026-05-26) | barrydeen only | Blob `1cc6c9ef…` is **identical** upstream and in ZC | **Yes** |
| `KeychainBackupService.swift` (123 lines) | `e9981c4` (2026-05-26) | barrydeen only | Upstream blob `20c9f9fe…` (Barry-only). ZC HEAD `8d01482b…` adds Seth's `bfa3ea3` (Remove Google Sign-In, +5/−8) | **Yes** for the upstream blob |

**Licence:** the same caveat as Phase 0. `wisp-ios` has no LICENSE file, and its README says MIT, © 2025 Barry Deen. Reusing it is a licensing decision for Seth.

**Cost of writing fresh (team recommendation):**
- Phase 0 already has NIP-44 v2 with a caller-supplied conversation key (`NIP44.encrypt(_:conversationKey:)`).
- So the new code is a thin Keychain wrapper of about 120 lines, plus PBKDF2 through CommonCrypto `CCKeyDerivationPBKDF` (~20 lines, only for variants a/b).
- Roughly one extra day including tests.
- It avoids the licence question entirely. Wisp stays a reference for behaviour only, with no copied code.

## 10. Verification

**Unit tests (M5):**
- every row of §7 driven through an injected Keychain and marker store, including "marker unreadable" and "Key missing never creates a key"
- sign-out stops when the Keychain delete fails
- backup encode and decode for the chosen variant
- variants a/b: wrong secret fails, and the PBKDF2 parameters are fixed

**Device checklist section G (Audit), per Seth's release gates:** device-only vs synchronizable items, iCloud recovery, account switching refusal, both sign-out paths and their failure handling, recovery failures, and:
- the primary item is absent on a second device restored from an encrypted Finder backup
- the backup item syncs to a second iPhone with iCloud Keychain on, and doesn't sync with it off
- restore through "I've used Grateful Day before"
- the not-arrived-yet path
- reinstall on the same phone finds the key, and no second key is created
- sign out keeps the journal; "Remove account and local data" deletes it, and stops before the journal if the key delete fails

## 11. Risks and open points

**PIN strength (corrected after Audit item 1):**
- Audit's estimate from public hashcat figures: about 8.8 MH/s for PBKDF2-HMAC-SHA256 at 999 iterations on one RTX 4090, which is about 15k guesses/s at 600k iterations.
- At that rate all 10⁶ six-digit PINs fall in **about 1–2 minutes**. My earlier "days" was wrong by about three orders of magnitude.
- Audit didn't measure this; it's derived from published figures.
- Only a high-entropy secret (variant a) protects a backup someone already holds.

**Other risks:**
- **iCloud Keychain off** is common. Those users get no working backup, and the app can't detect it. The copy has to carry that.
- **Sync lag on a new iPhone** is handled by the restore-first flow (§5).
- **External signers** (NIP-46) are out of MVP scope.
- **Interop:** nothing changes 36669 or 30078 events.

## Revision log
- r1 (2026-11-21, Sous): first draft.
- r2 (2026-11-21, Sous): Audit co-review items 1–6 and Chief's two additions.
  - §11: PIN strength corrected.
  - §9.1: options (a)/(b)/(c) with user costs; the recommendation changed to (c).
  - §5: iCloud Keychain can't be detected, so a write is never "backed up"; restore-first flow for sync lag.
  - §7: "marker unreadable" row added.
  - §6: confirmed Keychain delete before clearing the store; unreadable sync state counts as unsynced.
  - §3: the backup item uses `WhenUnlocked`.
  - §9.5: per-file provenance, and the cost of writing fresh (now the recommendation).
- r3.1 (2026-11-21, Sous): Audit r3 co-review. Owner-and-date rule, option (a): unique `entryKey` (owner|date), V4 custom migration, editor/calendar rules, tests. §7: key-missing/mismatch rows scoped to `connected`; "Connecting another account" row. Sign-out marker-write failure and remove-data journal-delete failure handling. §6a: no password content type, `changeCount` check, memory wording.
- r3 (2026-11-21, Sous): Seth's decisions (event 43dbe869) plus Chief's P13, P14/P14a, P15, P16 and Audit's three questions (event 58f98aaa). §6a import and §6b split added; isolation by per-entry owner. §6 rewritten: ordinary sign-out keeps the journal, separate "Remove account and local data", account isolation after sign-out. §9 records the decisions. §5: import of an existing key, existence check before create. §1/§8: affirmative choice; no claim that the journal is backed up. §7: "Signed out" row. Status active.
