---
title: "Grateful Day Device Test Scripts: Web Decryption and Keychain Recovery"
tags: [grateful-day, ios, device-testing, interop]
status: superseded
created: 2026-11-23
updated: 2026-11-24
---

> **SUPERSEDED 2026-11-24. Do not run on the primary iPhone.** "Remove account and local data" deletes every journal row, and the B-neg and cleanup steps assume no existing backup. Use `GRATEFUL_DAY_PHASE1_DEVICE_RUN_SHEET_2026_11_24.md`.

**READY to run on `main` `25d7f06`. Not yet run; nothing here is verified.** Updated 2026-11-24 by Ship (Chief request, event 5241eae3). Covers checklist items 1, 5, 10 and the R3 Saving-mark check in `PLANS/GRATEFUL_DAY_PHASE1_DEVICE_CHECKLIST.md`.

Base: `main` `25d7f06` = #18-#26 all merged (#22 last). On-screen labels below were read from source at `25d7f06`: `App/GratefulDay/Account/AccountCopy.swift`, `Sync/SyncCopy.swift`, `PrivacyStatement.swift`, `PublishDisclosure.swift`, `RootView.swift`, `PlaceholderScreens.swift`. Read through git, no checkout touched. Confirm against the built app; any mismatch is a finding, not a test failure.

## What changed since the 11-23 draft
- **There is no "Account" tab.** Tabs are **Today / Calendar / Settings**. Account is **Settings > Account** (`PlaceholderScreens.swift:10`). Every old "Account >" step now starts at Settings.
- Import flow is: "Use my Nostr account" > paste (a **Paste** button exists) > **Continue** > "This is the account npub1..." > **Use this account**.
- Negative case copy in Test B is the exact string "...your old journal key can't be restored here." (inside the "Your backup hasn't arrived from iCloud yet..." message), not a separate message.
- **Test B order changed** (see below): run the negative case first, or the TEST-B backup will show up on Device 2 and ruin it. iOS Keychain items also survive deleting the app, so "fresh install" never clears a key.
- Added install steps, item 10, and R3 as full scripts.

## Key facts
- Web login accepts only nsec, a NIP-07 extension, or a bunker:// URI (`gratefulday/src/components/auth/LoginDialog.tsx`).
- iOS has **no nsec export** (spec r3 unbuilt, awaiting Seth). iOS **can import** an nsec. So Test A uses a throwaway identity made outside the app and imported.
- iCloud Keychain backup is written only if the user taps "Back up to iCloud Keychain".
- Publishing: encrypted kind 36669; acks seen from nos.lol and relay.primal.net. Save quiet time is **30 s** after you stop typing (`SyncService.saveQuietTime`, `.seconds(30)`).
- Throwaway identities only. **Never Seth's real journal key.** Fake entries only, e.g. `interop test 2026-11-24 <time>`.

## Install via Xcode (both phones)
Needs: Mac with Xcode (27.2 installed here), USB cable or paired wireless device, Apple ID in Xcode > Settings > Accounts.
1. Make a clean tree at the tested commit without touching other checkouts: `git -C REPOS/grateful_ios worktree add ../grateful_ios-device-25d7f06 25d7f06` (detached). Confirm `git rev-parse --short HEAD` prints `25d7f06`. Record it.
2. Open `App/GratefulDay.xcodeproj`. Scheme **GratefulDay**. Bundle id `app.gratefulday.ios`; deployment target iOS 17.0; signing is Automatic and **no team is committed**, so pick your Team under Signing & Capabilities (do not commit that change).
3. iPhone: Settings > Privacy & Security > **Developer Mode** on (restarts the phone). Trust the Mac when asked.
4. Choose the phone as run destination, Product > Run (Release config is closer to what users get: Product > Scheme > Edit Scheme > Run > Build Configuration = Release). First launch: Settings > General > VPN & Device Management > trust your developer profile if prompted.
5. Repeat for Device 2 (Test B). Free personal-team installs expire after 7 days; fine for this.
6. Record: commit, config, iOS version of each device. TestFlight is not used.

## Shared prep (10 min)
1. Create three throwaway identities in a password manager: **TEST-A** (nsec made on web signup or any Nostr tool; note npub), **TEST-B** and **TEST-C** are created inside the app (Test B).
2. Dark and light mode both available; note which is active in screenshots.

## Item 10 first: Today footer clear of the tab bar (5 min, no account)
Do this on a fresh install before connecting anything, so the "On this iPhone only" footer is on screen.
1. Fresh install, no account. Today tab. Type a fake entry long enough to need scrolling (or add several notes), or rely on small-screen scroll.
2. Scroll Today to the very bottom. **Pass:** "On this iPhone only" is fully readable above the tab bar (the app leaves 96 pt of room, `tabBarClearance`).
3. Muted text legible in **light** mode (P57: hsl 25,15,40). Also glance at dark.
4. Screenshot dated, per device. Smaller screen: a small iPhone if you have one; an Xcode Simulator (e.g. iPhone SE) is acceptable but label it "simulator".
5. Later, after connecting an account (Test A), repeat the scroll check with the **Saving to your account** mark showing in the footer position.

## Test A: iOS to web decryption, same identity (item 1, also R3)
**Needs:** 1 iPhone on this build, signed out / fresh; TEST-A nsec in the iPhone clipboard (Universal Clipboard from the Mac, or the Paste button; the app says "If you copied it on a Mac, it may still be on that Mac's clipboard."); a desktop browser with the web app; nos.lol and relay.primal.net reachable.

1. iPhone: **Settings > Account**. Under "Keep your reflections safe" tap **Use my Nostr account**. Paste the TEST-A nsec, tap **Continue**. Confirm "This is the account npub1..." matches TEST-A. Tap **Use this account**.
2. Publishing sheet "What's private in your journal": tap **Continue**. (**Not now** publishes nothing.)
3. If the backup offer appears ("Keep a backup of your journal key?"): tap **Don't back up**, then **Continue without backup** (keeps Test A independent of Test B).
4. Today: write the fake entry. Stop typing and wait about 30 s, app in foreground.
5. **R3 Saving mark:** "Saving to your account" appears once and clears after sync; no flicker while typing; readable. Tap it once while visible: detail text "This reflection hasn't finished saving to your account...". Screenshot with date.
6. Web: log in with the TEST-A nsec. Open the same day.
7. Entry text is readable and identical.
8. Negative: log in on web as a different throwaway identity and open the TEST-A entry link. It must show the encrypted/unavailable state, never plaintext.
9. Cleanup on the phone: Settings > Account > **Remove account and local data**, then **Remove**, confirm **Delete**. (No backup exists, so no "Delete the iCloud backup" step.)

**Pass evidence (all required):** screenshot of iOS text and web showing identical text (same date, same npub); relay lookup showing kind 36669 event id on at least 2 relays; event content is ciphertext (no plaintext); negative-check screenshot; R3 screenshot.
**Fail signals:** web "unavailable" for the correct identity; garbled text; entry missing after 2 min; plaintext in a relay event; Saving mark flickers or never clears. Record event id, which relays have it, and web console error. File to Sous.
**Optional (item 2):** write an entry on web, foreground iOS, pull to refresh or wait, confirm it decrypts on the phone.

## Test B: Keychain recovery on a second device (item 5)
**Needs:** iPhone 1 + a second Apple device on the **same Apple ID**, both with iCloud Keychain on (Settings > your name > iCloud > Passwords & Keychain), both on this build. One device only = cannot complete; record as partial (same-device restore proves nothing about sync).

**Run the negative case first, then the positive case.** Otherwise TEST-B's backup appears on Device 2 and the negative case can't be shown.

### B-neg: no backup, Device 2 must not invent an account (about 15 min)
1. Device 1: Settings > Account > **Create a journal key** > **Make a new key**. Accept the publishing sheet (**Continue**). At the backup offer tap **Don't back up** > **Continue without backup**. This is TEST-C. Note npub. Write a fake entry; wait for sync.
2. Device 2 (fresh, no account): Settings > Account > **I've used Grateful Day before**. Wait through "Looking for your journal key backup...".
3. **Pass:** after the wait it shows "Your backup hasn't arrived from iCloud yet... If you never made a backup, your old journal key can't be restored here." with **Try again** / **Back**. No account created, no key made silently. Screenshot.
4. Device 1: Settings > Account > **Remove account and local data** > **Remove** > **Delete** (no backup exists).

### B-pos: backup found and restored
1. Device 1: Settings > Account > **Create a journal key** > **Make a new key**. Publishing sheet **Continue**. Backup offer: **Back up to iCloud Keychain**. Confirm "Journal key backup saved. It reaches your other devices if iCloud Keychain is on...". This is TEST-B. Note npub; write a fake entry; wait for sync (Saving mark gone).
2. Note the time. Wait for Keychain sync (minutes, can be longer).
3. Device 2 (fresh, signed out): Settings > Account > **I've used Grateful Day before**. After "Looking for your journal key backup...":
   - "We found your journal key backup." and a row "Backup from <date>": tap **Restore**.
   - If instead "Your backup hasn't arrived...": wait 5 min, **Try again**. Stop at 30 min and record fail/inconclusive.
4. Device 2 npub equals Device 1 npub.
5. The Device 1 entry appears and is readable on Device 2 after a sync (up to a few minutes; foreground the app).
6. Cleanup (both devices): Settings > Account > **Remove account and local data**, and when asked "Also delete the iCloud backup of your journal key?" choose **Delete backup** so no TEST key lingers in the real Keychain.

**Pass evidence (all required):** screenshots of Device 1 "backup saved" + npub; Device 2 "found" + same npub; Device 1 entry readable on Device 2; minutes from backup to "found"; B-neg screenshot.
**Fail signals:** nothing found after 30 min with Keychain on; npub differs; entry unreadable after restore; restore creates a new key silently. Capture in-app message text and iOS version.

## Results log (fill in, dated, with evidence links)
| Item | Result | Date | Evidence |
|------|--------|------|----------|
| 10 footer + tab bar (device) | | | |
| 10 smaller screen | | | |
| R3 Saving mark | | | |
| 1 iOS to web decrypt | | | |
| 5 Keychain recovery + B-neg | | | |

Ship moves items to Verified in the checklist only with the evidence above.

## Open questions for Seth (blocking; asked in Chief's thread)
1. A second Apple device on the same Apple ID for Test B?
2. OK to use throwaway identities (scripts never touch the real journal account)?
3. Install through Xcode (not TestFlight)?
Not blocking: key-export r3, D-R1 (`relay.nostr.band`), the two `probe/p62-*` branches.
