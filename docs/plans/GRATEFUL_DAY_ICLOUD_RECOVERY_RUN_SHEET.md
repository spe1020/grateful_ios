---
title: "Grateful Day iCloud Keychain Recovery Run Sheet"
tags: [grateful-day, ios, device-testing, recovery]
status: active
created: 2026-11-25
---

**Seth runs this. Agents don't.** Phase 1 exit criterion 2. Replaces step 3 of `GRATEFUL_DAY_PHASE1_RECOVERY_RUN_SHEET_2026_11_25.md`.
Build: iOS `a254289`. All quoted screen text was checked against source at `10ae4d6`; none of the strings checked is missing at `a254289`. Between `10ae4d6` and `a254289`, `KeyVault.swift` and `Keychain.swift` didn't change. The Account screen gained **Advanced > Use your journal key in another app** (key export): **don't open it in this run.** **Seth reported a restore PASS on 2026-11-27**, before `a254289` was merged (see the result record; details pending). That row's build is whatever Seth reports; this line doesn't set it. If the app says something different, record it.

## Decide first: which device is Device 1
Device 1 creates a new disposable identity. **Your primary iPhone can't be Device 1 or Device 2:** either role means switching its account.

| Setup | What it proves | |
|---|---|---|
| **A. Two non-primary devices** (iPhone, or iPad running the iPhone app) | Explicit backup, sync, restore, decrypt: all of section 5 | **Approved by Seth (F, 8a3b1c2b).** Needed for PASS on this sheet |
| B. One non-primary device + the older throwaway backup from the first session | Restore of an old backup only. The act of backing up isn't re-tested, and it needs that backup's recorded npub and a saved reflection | Fallback. Needs your approval to count for exit criterion 2 |

With only one spare device and no approval for B, record **BLOCKED: no second non-primary device**. A Simulator never counts.

## Have on hand before you start
1. Device 1 and Device 2: physical, iOS 17 or later, charged, on a working network, **each with a passcode**.
2. Both signed in to the **same Apple Account**.
3. On both: Settings > your name > iCloud > Passwords (and Keychain) > iCloud Keychain sync **on**. Finish any Apple approval prompt. Menu names vary by iOS version.
4. Neither device has a Grateful Day account or any written entry (guest entries would be adopted by the new identity). If one does, stop. Don't remove anything to make room. Deleting and reinstalling the app doesn't make a device clean. A key can stay in the Keychain, and the app then opens connected. Part 1 step 1 / Part 2 step 1 catch this: if an account shows, stop.
5. A Mac with Xcode, a cable, Developer Mode on both devices, your signing team **Z26TJQZZWC** (the one in your local checkout), bundle ID `app.gratefulday.ios`.
6. A private note for: the new npub, the date, times. **No nsec is needed; don't write one down.**
7. A made-up test line you'll recognize. No real journal text.
8. About 45 minutes, with 30 of them possibly spent waiting for iCloud.

## Build (both devices)
1. `git -C <your grateful_ios checkout> fetch origin`
2. `git -C <your grateful_ios checkout> worktree add ../grateful_ios-recovery a254289` (a separate folder, so your working checkout and its local changes aren't touched)
3. In it, `git rev-parse --short HEAD` must print `a254289`.
4. Open `App/GratefulDay.xcodeproj`, scheme **GratefulDay**, pick your team (don't commit that), Run on each device. **Check the Run destination every time. Never select the primary iPhone.**

## Part 1: Device 1 (create, back up, write)
1. **Settings > Account.** Expect **I've used Grateful Day before**, **Create a journal key**, **Use my Nostr account**. If an account shows, stop. Screenshot.
2. Tap **Create a journal key**. In "Make a new journal key?" tap **Make a new key**.
3. "Keep a backup of your journal key?": tap **Back up to iCloud Keychain**. Expect "Journal key backup saved. It reaches your other devices if iCloud Keychain is on (Settings → your name → iCloud → Passwords & Keychain)." Record the time. Screenshot. This message means saved on this device, not yet synced.
4. "What's private in your journal" appears: tap **Continue**.
5. **Settings > Account:** record the shortened npub (first 12 characters, "…", last 6). No **Back up journal key** button should show. Screenshot.
6. **Today:** write the test line. Stop typing, keep the app open about a minute, until the **Saving to your account** mark clears. Record the date and time. Screenshot with the text covered.
   - Mark still there after 10 minutes with the app open: record **BLOCKED: reflection not saved to account**. Don't go on.
7. Optional but useful: send the team the npub (public). An agent can then look up the event ID and which relays hold it. Without this, the event ID is recorded as pending.
8. Leave Device 1 as it is. Don't sign out, don't remove anything.

## Part 2: Device 2 (discover, restore, decrypt)
1. **Settings > Account:** the same three buttons. If an account shows, stop.
2. Tap **I've used Grateful Day before**. Expect "Looking for your journal key backup…". **Never tap Create a journal key** ("Make a new journal key?" → **I've used it before** if you do).
3. What you see:
   - "We found your journal key backup." → tap **Restore**. First check it's the only choice; the app can't show whose it is until after restore.
   - Several rows "Backup from <date>" → your Apple Account holds more than one backup. Pick today's, newest first. Rows show a date only.
   - "Your backup hasn't arrived from iCloud yet. Make sure iCloud Keychain is on in Settings, then try again. If you never made a backup, your old journal key can't be restored here." → **delayed sync**, below.
   - "One backup couldn't be read, so it isn't listed. It hasn't been deleted." → record it; not a fail by itself.
4. Restore is silent: the sheet closes. If "What's private in your journal" appears, tap **Not now**. Reading doesn't need it.
5. **Settings > Account:** compare the shortened npub with Part 1 step 5. Screenshot.
   - Different npub: if you picked from several rows, use **Sign out** only (never Remove), record the wrong pick, and retry once with another row dated today. A different npub when only one row was offered is a FAIL: stop.
6. Keep the app open for a minute. Open **Today** (or the Part 1 date in **Calendar**). Don't edit. Screenshot with the text covered; record "matched" or "did not match".

### Delayed sync
1. Wait 5 minutes, tap **Try again**. Repeat up to **30 minutes** from the backup time in Part 1 step 3. Between tries, check that iCloud Keychain is on for both devices, that both are online and unlocked, and that Apple isn't asking for approval.
2. You may close and reopen the app. After **Back**, "Still looking for your journal key backup." on Today is expected.
3. **Don't tap Use my Nostr account** (that's nsec import, not recovery), and don't create a key.
4. At 30 minutes: **INCONCLUSIVE**. Leave both devices as they are; you can retry later without redoing Part 1. Record whether another iCloud Keychain item (such as a saved password) had reached Device 2.

## Result
| # | PASS needs | FAIL |
|---|---|---|
| R1 | Backup saved on Device 1 (the saved message) | "Couldn't save the key." |
| R2 | Device 2 lists the backup within 30 minutes | (not found in 30 minutes = INCONCLUSIVE, not FAIL) |
| R3 | Device 2's npub equals Device 1's | A different key with only one row offered, or a new key made without being asked |
| R4 | The earlier reflection opens on Device 2 with identical text | "We can't open this day's reflection from your account on this iPhone…", wrong text, or no entry after reopening the app and 5 minutes online |

- **PASS:** all of R1 to R4, setup A.
- **FAIL:** any FAIL cell, or "Couldn't save the key." after Restore.
- **BLOCKED:** a prerequisite is missing, or Part 1 couldn't finish.
- **INCONCLUSIVE:** backup not found in 30 minutes, or anything that stopped you judging R2 to R4.
- Phase 1 criterion 2 closes only on PASS.

## Send back
Date and times (backup, found), both device models and iOS versions, `a254289`, both shortened npubs, which rows Device 2 showed, R1 to R4, screenshots. **No nsec, no reflection text.**

## Never, during or after
No **Remove account and local data**. No **Delete backup**. No deleting Keychain items or the app. No reset. Nothing on the primary iPhone. Leave the test accounts and the new backup in place; cleanup needs your explicit go. The new backup will also sync to your primary iPhone's iCloud Keychain if your primary iPhone uses the same Apple Account. That's expected; do nothing with it.

## Result record (physical devices only)
| Date | Setup | Devices / iOS | Build | R1 | R2 (minutes) | R3 | R4 | Overall | Evidence |
|---|---|---|---|---|---|---|---|---|---|
| 2026-11-27 (reported) | not stated | not stated | not stated | | | | | **PASS, user-verified** (Seth 3459b698; recorded per Chief 3e8db74a) | Seth's report only. R1–R4 not itemized; details and screenshots pending |
