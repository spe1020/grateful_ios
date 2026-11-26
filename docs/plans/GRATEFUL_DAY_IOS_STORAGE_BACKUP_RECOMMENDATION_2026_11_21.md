---
title: "Grateful Day iOS — Local Storage, Backup Exclusion and Key Storage Recommendation"
tags: [grateful-day, ios, storage, privacy, backup, keychain]
status: active
created: 2026-11-21
---

Owner: Sous. Validation: Audit. Requested by Chief, D11 (buzz://message?channel=9a37a94b-4f0e-4237-bbc7-c1fe3a4ee887&id=02116bfc2cc38256ef1d586b826efe2bdba99167febee0d192d390a6af14acca).

**What this implements:** Seth's decision that "for the MVP, unencrypted local gratitude drafts are excluded from iCloud backups until we've established and verified an appropriate privacy and recovery approach" (buzz://message?channel=9a37a94b-4f0e-4237-bbc7-c1fe3a4ee887&id=fa4a61cecc05b0a754631f5418b201f83426741363cdcc6db06591c4064ed6e1). It also implements the requirements in `PLANS/GRATEFUL_DAY_IOS_MVP_RECOMMENDATION_2026_11_21.md` §"Local drafts are not backed up" (items 1–5).

**Scope:** this is a recommendation only. No backup or recovery mechanism is proposed or built. The store itself is Phase 1 work; Phase 0 (no UI) doesn't touch it.

**Status of claims:** platform behavior marked **[verify]** comes from Apple's documented behavior as I understand it, and it must be confirmed on a device (see §7) before the user-facing copy relies on it.

## 1. Where drafts live

- **Location:** one SwiftData store (the default choice in the tech discovery doc) at a fixed URL, `Application Support/GratefulDay/Store/journal.store`, set with `ModelConfiguration(url:)`.
  - The `Store/` directory holds **everything that contains reflection text**: entries, unsynced edits, the conflict archive (the "earlier version" copies) and the outbox of signed-but-unsent events.
  - SQLite sidecar files (`-wal`, `-shm`) are created in the same directory.
- **CloudKit off, explicitly (Audit S1):** `ModelConfiguration(..., cloudKitDatabase: .none)`. The default is `.automatic`, which would start mirroring reflection text to CloudKit by itself if the app ever gains an iCloud/CloudKit entitlement. The backup exclusion doesn't cover that. A unit test checks the setting (§7.1).
- **Open the store only when protected data is available (Audit S2):** never in `App.init` or eagerly at startup. iOS can launch the app before first unlock (for example, prewarming on iOS 15+), and a `.complete` store can't be opened then.
  - Open it when `UIApplication.shared.isProtectedDataAvailable` is true and the scene is active.
  - Otherwise wait for `protectedDataDidBecomeAvailable`.
  - Until then, show a neutral locked/loading state, never an empty journal.
- **Not** `Library/Caches` or `tmp`. Both are excluded from backup, but the system may purge them when storage is low, which would silently delete a user's only copy.
- **Not** UserDefaults, not the app group container, not files in `Documents/`. `Documents` is exposed to the Files app if file sharing is ever turned on, and it is backed up.

## 2. Keeping drafts out of iCloud and Finder backups

- On every launch, before the store opens: create `Store/` if it's missing, then set `URLResourceValues.isExcludedFromBackup = true` on the **directory**.
  - Setting it on the directory excludes everything inside it, including sidecar files SQLite creates later **[verify]**.
  - It's re-applied on every launch because the attribute is lost if the directory is ever recreated, and setting it again costs nothing.
- **If setting the attribute fails (Chief P10, implemented in M3a):**
  - The store still opens. Refusing would lock users out of their only copy.
  - The failure is logged without content: a fixed message, the directory name and the error domain/code.
  - `JournalStore.backupExclusionFailed` is set.
  - The exclusion is retried on every foreground, not just cold launch. The flag clears when a retry succeeds.
  - While the flag is set, Settings → Privacy and the Today "On this iPhone only" sheet show the alternate statement (Prep's copy). They never say reflections are left out of backups.
  - Tests inject a failing call and check each of the above.
- **Protection-class failures (P10.5):** handled the same way, minus the copy change.
  - This covers both the `Store/` directory attribute and `.complete` on each store file.
  - The store still opens. Before M3a, a `protectFiles` failure set `.failed` and locked the user out.
  - Each failure is logged with the file name and error code.
  - `JournalStore.protectionFailed` is set, retried every foreground and cleared on success.
  - There is no UI state, because no copy claims locked-device encryption. The flag blocks any future such claim.
- Simulator tests prove only that the attributes are set and re-applied. A real backup omitting the folder, coverage of the SQLite sidecars, and Quick Start behaviour remain **physical-device release gates** (Seth, event 35ef16eb). Until they pass, store and marketing copy must not claim backup exclusion or encryption. Details: `PLANS/GRATEFUL_DAY_IOS_BACKUP_EXCLUSION_FAILURE_2026_11_21.md`.
- **Covers:** iCloud Backup, and Finder/iTunes backups, both encrypted and unencrypted **[verify]**.
- **Direct iPhone-to-iPhone transfer (Quick Start):** I expect excluded items not to transfer, because transfer is built on the backup mechanism **[verify]**. The MVP copy already assumes they don't (MVP item 1). If the device test shows they *do* transfer, the copy is still safe: it only promises less than what happens. Prep should know either way.
- **What still gets backed up, by design:** UserDefaults, limited to non-sensitive flags (onboarding seen, the privacy-default boolean, relay preferences). **No reflection text, dates of entries, counts or streak data in UserDefaults.** Even the dates someone journals are personal.

## 3. File protection class

- **`NSFileProtectionComplete` for `Store/`.**
  - It's set on the directory at creation (`FileAttributeKey.protectionKey: .complete`).
  - It's also set app-wide with the Data Protection entitlement (`com.apple.developer.default-data-protection = NSFileProtectionComplete`), so new files are covered even if the directory attribute doesn't carry over to them **[verify]**.
- **Effect:** files are encrypted with a key derived from the device passcode and can't be read while the device is locked.
- **Consequences:**
  - **No background sync while the device is locked.** The MVP only syncs in the foreground, so nothing is lost. If background sync is added later, it needs its own review: the alternative class `CompleteUntilFirstUserAuthentication` is weaker.
  - The app observes `protectedDataWillBecomeUnavailable` and finishes any in-flight save before it locks.
  - **Users without a device passcode get no file encryption.** This is outside the app's control and goes in Audit's residual-risk list.
- **App-level encryption of the store** (a store key held in the Keychain): **not recommended for the MVP.** Complete protection already encrypts the files at rest. App-level encryption mainly helps if a later change misconfigures the protection class or adds backups, and the backup case is exactly when it's worth adding. That's the "encrypted local-backup approach" the MVP marks as *revisit when*, and it belongs to that future decision.

## 4. Keychain (the Nostr key)

- **Item:** `kSecClassGenericPassword`, a service unique to Grateful Day, with:
  - `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
  - `kSecAttrSynchronizable = false`
- **What that means:**
  - The key isn't in iCloud Keychain.
  - It isn't restored to a *different* device from any backup, and it can't be read while the device is locked **[verify for encrypted Finder backups restored to the same device]**.
  - Same flag as the reference implementation (`zapcooking_ios` `NostrKey.swift:197` @ `6353172`), written fresh (see the provenance inventory).
- **When a key exists:** I recommend **no key until the user connects an account**, rather than a silent key at first launch.
  - Drafts are plaintext under file protection either way, so a silent key adds no protection before sync.
  - It would create an identity the user can lose without knowing they had it.
  - Prep left this to Sous and Audit (MVP §"Silent local key"), so Audit decides.
- **Biometric gate** (`SecAccessControl` with `.userPresence`): optional, off for the MVP. Prep/Audit can add it later without changing storage.
- **Never** in UserDefaults, logs, crash reports, analytics, the pasteboard (except a user-initiated export, which needs its own review), or SwiftData.
- **Reinstall behavior (needs Audit's call):** iOS Keychain items can survive deleting the app.
  - **Keeping them:** a reinstall restores the account.
  - **Wiping them on first launch after reinstall:** that may destroy the user's only copy of the key.
  - **I recommend keeping them**, with no silent wipe. Audit agreed, on condition S3:
    - Account removal includes an explicit **"Remove key from this iPhone"** step that deletes the Keychain item.
    - No copy may say or imply that deleting the app erases the user's identity or key.

## 5. What a user loses if the device is lost, replaced, reset, or the app is deleted

| Situation | Synced entries (on relays) | Unsynced entries and edits | Ability to read private entries elsewhere |
|---|---|---|---|
| No account | — | **Lost** | — |
| Account, key also kept somewhere else (web signer, exported nsec) | Kept | **Lost** (only what hadn't reached a relay) | Kept |
| Account, key only on this iPhone | Still on relays, but public ones can't be edited and private ones can't be read | **Lost** | **Lost**: the key was device-only |

- **App deleted:** local data is gone, as in "lost device". Whether the Keychain survives is covered in §4.
- **MVP item 8 says key backup is required.** That's a *key* backup or recovery step, separate from Seth's exclusion of *drafts* from backups, and no design for it is proposed here. Building it needs Seth's review under his "no unreviewed backup or recovery mechanism" rule. Until then, row 3 is the honest description, and Prep's copy must not imply otherwise.

## 6. Other places reflection text could leak (MVP rules)

- **App switcher snapshot:** cover the window on `sceneWillResignActive`, per the tech discovery doc.
- No Core Spotlight indexing, Siri/App Intents donations, widgets, Live Activities or notifications that contain reflection text.
- **Logging:** never log content. Use `os_log` with `privacy: .private` for anything that touches entries, and send no third-party crash or analytics SDK any entry data.
- **Exports** (an MVP phase 2 idea) need their own review. A written file can be backed up, which would undo this design.

## 7. Verification (before the copy goes live; Audit to validate)

1. **Unit or integration test** on launch:
   - `Store/` has `isExcludedFromBackup == true`.
   - Each file in it (the store, `-wal`, `-shm`) reports `FileAttributeKey.protectionKey == .complete`.
   - The `ModelConfiguration` in use has `cloudKitDatabase == .none` (S1).
2. **Finder encrypted backup on a test device:** write a reflection, back up, then restore to a *second* test device.
   - Expect no journal content.
   - Expect the UserDefaults flags to be present.
   - Expect no Keychain key on the second device.
3. **iCloud:** Settings → [name] → iCloud → Manage Storage → Backups → this iPhone should show Grateful Day at about 0 KB after entries exist.
4. **Quick Start transfer** to a second device: record what carries over and report it to Prep.
5. **Locked device:**
   - With the store open and the device locked, confirm reads fail gracefully (no crash, no data loss) and that the app recovers on unlock.
   - **Cold launch while locked (S2):** reboot the device and trigger a launch before first unlock (prewarm, or a debugger-attached launch). The store must not open and nothing may be written; after unlock it opens normally and shows the journal.
6. **Keychain removal (S3):** "Remove key from this iPhone" deletes the item; confirm a reinstall afterwards finds no key.

## 8. Decisions requested

| # | Decision | Owner |
|---|---|---|
| 1 | Validate §§1–4 and §7 | Audit: **validated** with S1 and S2, both now applied (buzz://message?channel=9a37a94b-4f0e-4237-bbc7-c1fe3a4ee887&id=dc5c634130a83a0be656bfacc56ec2293728e4035af1d7711d170ddbf51c644e) |
| 2 | No key until the user connects an account (vs. a silent key) | Audit: **agreed**. Prep to be informed |
| 3 | Keep Keychain items across reinstall | Audit: **agreed**, on S3 (applied in §4 and §7.6) |
| 4 | How key backup (MVP item 8) is designed and reviewed, given the "no unreviewed recovery mechanism" rule | Seth (via Chief) |

## Revision log

- r2 (2026-11-21): Audit validation applied. S1: `cloudKitDatabase: .none` and its test. S2: open the store only when protected data is available, plus a cold-launch-while-locked test. S3: "Remove key from this iPhone" and a copy rule. Device tests in §7 are still pending.
- 2026-11-21 (Sous): §2 failure handling updated to Chief P10/P10.5 as implemented in M3a (`phase1/m3a-today-editor`). Audit to validate.
