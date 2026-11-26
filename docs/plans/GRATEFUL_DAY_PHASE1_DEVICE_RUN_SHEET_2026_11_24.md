---
title: "Grateful Day Phase 1 Remaining Device Test Sequence"
tags: [grateful-day, ios, device-testing, interop]
status: superseded
created: 2026-11-24
---

> **SUPERSEDED 2026-11-25** by `GRATEFUL_DAY_PHASE1_RECOVERY_RUN_SHEET_2026_11_25.md`. Results and steps there.

Owner of device steps: Seth. Prepared by Ship from Seth's handoff (event 38e89e0d). Nothing below has been run.
Source read: iOS `25d7f06` (= origin/main), web `898630f` (= origin/main; latest github-pages deployment listed by GitHub). PR #45 is not deployed. iOS #28 is test-only, so no iPhone rebuild is needed for it.

Replaces the run order and cleanup steps in `GRATEFUL_DAY_DEVICE_TEST_SCRIPTS_WEB_DECRYPT_AND_KEYCHAIN_RECOVERY.md`.

## Current state (checked 2026-11-25 01:59 UTC; this replaces older state below where they differ)
- Web main `0b5e5e6` (#45). Its GitHub deployment is marked failure; gratefulday.space Last-Modified is still 2026-11-24 00:51:18 GMT, matching the successful `898630f` deploy.
- iOS main `4d6ccf9`. Compared with `25d7f06`, only `ImportThenWriteTests.swift` changed, so no iPhone rebuild is needed.
- #46 open and CLEAN at `9019648`; merging it triggers a web deploy that includes #45. #47 is a draft at `ce03779`. #27 is not merged.
- **Step 1 can be done now.** Before starting, check whether a deploy has succeeded since this note:
  - No: follow step 1 as written (one reload).
  - Yes: wait about 10 s after login and check the entry BEFORE any reload; record that as step 4. If it doesn't appear, reload once and continue step 1. Record the deployed commit, not `898630f`.
- Safety rules stay in force until this sheet says otherwise, even after #27 merges.
- **Keep the no-switch rule after #29 (the #27 fix) merges and is installed:** #29 does not migrate older rows, so ownerless days written on this iPhone before it, including any written while an account was connected, can still be adopted by another account (Audit event 0a835ee3; Chief ruling event 72279230).

## Status update (checked after Seth's approval, event 6df124c6)
- #45 merged (`0b5e5e6`), #28 merged (iOS main `4d6ccf9`; only adds a test file, so a `25d7f06` build has the same app code).
- #45 is NOT deployed: Pages run 45527365925 failed at "Deploy to GitHub Pages" ("No artifacts named github-pages were found"). gratefulday.space returned Last-Modified 2026-11-24 00:51:18 GMT, consistent with the earlier `898630f` deploy. Step 1 keeps the one-reload workaround. Step 4 waits for a successful deploy; recheck before running it.
- #27 / #44 / author check: approved to build, not yet merged. Safety rules below still apply.

## Safety rules for the primary iPhone
- Do NOT tap **Remove account and local data**. `removeAccountAndData` deletes the whole journal store: every row, all accounts. The app has no nsec export.
- Do NOT delete the app (journal goes with it; Keychain items can survive). Do NOT sign out or switch accounts for these steps (#27).
- Never choose **Delete backup** for an existing identity's iCloud backup.
- No nsec or reflection text in screenshots, logs, issues or chat that will be shared. Blur entry text; record "matched / did not match".

## 1. Web decryption, identity C (now; no merge, no deploy)
1. On iPhone confirm C is connected and today's/test day's "Saving to your account" mark is gone. Note date of the entry. Change nothing.
2. Desktop: new private window, no other identity used in it (avoids #44). Open the production web app. Open the browser console.
3. Log in as C (your usual method: nsec, extension or bunker).
4. Wait about 10 s. Console should show "Syncing relay list from Nostr:" with C's relays.
5. Reload ONCE (production lacks #45; reload makes it use the synced list). If the reload ends the login, log in again in the same window.
6. Open the entry's date. PASS: text readable and identical to the iPhone. Do not edit, save, delete, or change relay settings.
7. Evidence: date/time, C's npub, web commit 898630f, match yes/no, screenshot with text blurred.
- Fail triage: no "Syncing relay list" line = web did not find/apply C's kind 10002 from its default relays (relay discovery, not yet a decryption result). Line present but entry missing or "unavailable" = record event id, relays, console error (no plaintext) and report.
- Close the private window afterwards.
- A pass covers iOS -> web decryption for C only. It does not cover web -> iOS, conflicts or deletion.

## 2. Light mode (same sitting)
1. iPhone: system Settings > Display & Brightness > Light. App follows system.
2. Today scrolled to bottom: footer line fully above the tab bar; muted text readable (checklist item 10, connected state). Check Calendar and Settings too.
3. While making no new entry on C, the Saving mark (R3) may not appear; record "not observed". Do not write an entry just to force it unless you want a new real event on C.
4. Web (light is the default theme): calendar and day view muted text readable.
5. Switch back to your normal appearance. Evidence: dated screenshots, text blurred.
6. Guest-state footer and smaller screen: Xcode Simulator (iPhone SE) with fake text, labelled "simulator". Not on the primary iPhone.

## 3. Keychain recovery (needs a second Apple device, same Apple ID, iCloud Keychain on)
Positive case needs NO action on the primary iPhone: it restores the backup made in the first device session (reported by Seth; existence not re-verified).
1. Device 2: no Grateful Day account on it, build `25d7f06` from Xcode. If it already holds a journal or key, stop and report.
2. Settings > Account > **I've used Grateful Day before**.
3. If one backup: **Restore**. If several "Backup from <date>": pick the first-session date. If none: wait 5 min, **Try again**; stop at 30 min, record inconclusive.
4. PASS: restored npub equals the original test identity's npub, and its synced entry appears readable. If a publishing sheet appears, record it; Continue only on this otherwise empty device.
5. Leave Device 2 connected. If you do remove it later, choose **Keep backup**.
- No second device: record BLOCKED. A same-device restore does not prove sync.
- Negative case ("old journal key can't be restored here"): invalid on any device that receives your iCloud Keychain while a backup exists. Do not delete a backup to force it. A Simulator not signed in to iCloud can show the message, labelled "simulator"; that is a UI check, not proof about iCloud.

## 4. After #45 (only if Seth approves merge + deploy)
Fresh private window, log in as C, do NOT reload. PASS: relay list syncs and the entry appears. Record deployed commit. Do not test account switching in one window as a #45 check; that is #44.

## Not in this round (still untested)
Web -> iOS sync (writes a new version; agree identity first), cross-device conflict, deletion/archived versions, account separation/removal (spare device or simulator only), Data Protection, VoiceOver, background/foreground, post-account responsiveness (P53).

## Results
| Step | Result | Date | Build/commit | Evidence |
|---|---|---|---|---|
| 1 Web decrypt, C | | | | |
| 2 Light mode iOS | | | | |
| 2 Light mode web | | | | |
| 2 Simulator footer, small screen | | | | |
| 3 Keychain restore | | | | |
| 4 No-reload retest | | | | |
