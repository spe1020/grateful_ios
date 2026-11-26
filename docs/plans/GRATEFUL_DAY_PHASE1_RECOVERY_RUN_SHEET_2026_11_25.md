---
title: "Grateful Day Phase 1 Recovery and Remaining Device Tests"
tags: [grateful-day, ios, device-testing, recovery]
status: active
created: 2026-11-25
---

> **2026-11-25 update:** step 3 (recovery) is replaced by `GRATEFUL_DAY_ICLOUD_RECOVERY_RUN_SHEET.md`. Steps 4 to 6 are now the simulator scenarios in `GRATEFUL_DAY_PHASE1_TEST_RUN_SHEET.md` (Sous runs them). Results are recorded there.

Owner of device steps: Seth. Prepared by Ship (Chief handoff 34b024d2, Seth bc767b8f, Prep input 79bfcf89, decision log P86). Successor to `GRATEFUL_DAY_PHASE1_DEVICE_RUN_SHEET_2026_11_24.md`.

Code: iOS main `c9101349`; web main `9347018` (live: deployment 8057856117; gratefulday.space Last-Modified 2026-11-25 12:46:09 GMT as returned on 2026-11-25). Expected behavior below comes from reading source at these commits. **Steps 3 to 7 have not been run.** A mismatch with the app is a finding; record it.

## Results so far (steps 1 and 2)
| Step | Result | Date | Build / commit | Evidence |
|---|---|---|---|---|
| 1 iOS → web private decrypt, identity C (`npub1jlag3…`), reflection dated 2026-11-24 | **USER-VERIFIED PASS** | 2026-11-25 (exact time: Seth to confirm) | Web `9347018` (Seth: #45 was live; exact commit inferred from deploy time, P86). iOS build: **pending from Seth** | Seth's report, event bc767b8f: auto-sync, Saving mark cleared, 5 relay acks, fresh private window, matched. Screenshots/logs **pending** |
| 1b Entry appears without a manual refresh (old sheet step 4) | **USER-VERIFIED PASS** | 2026-11-25 | Web `9347018` | Same report |
| 2 iPhone light mode: Today footer above tab bar, gray text readable, Today/Calendar/Settings | **USER-VERIFIED PASS** | 2026-11-25 | iOS build pending from Seth | Seth's report, bc767b8f. Screenshots pending. Earlier dark-mode footer check also passed (Seth) |
| 2 Web light mode | not reported | | | |
| 2 Small-screen footer (Simulator) | not reported | | | |

Step 1 covers C, iOS → web, private only. It says nothing about web → iOS, account switching, conflicts, deletion or recovery.

## Rules for every step below
- **Primary iPhone: do nothing on it** for steps 3 to 6.
- **Never tap "Remove account and local data"** on any device. **Never tap "Delete backup".** Never delete a Keychain backup. Do not uninstall the app from the primary iPhone.
- The no-account-switch rule stays on the primary iPhone: days written before #29 with no owner are not migrated and can still be adopted by another account.
- Throwaway identities only. Never Seth's real journal key. Made-up entry text only.
- No nsec or entry text in screenshots, logs, issues or chat. Blur text and record "matched / did not match". npubs are fine.
- No destructive cleanup. Leave test accounts and backups where they are unless Seth approves removal.

## Build (used by all steps)
1. `git -C ~/.buzz/REPOS/grateful_ios worktree add ../grateful_ios-device-c9101349 c9101349` (detached; skip if it exists).
2. In it, `git rev-parse --short HEAD` must print `c910134`. Record it.
3. Open `App/GratefulDay.xcodeproj`, scheme **GratefulDay**, pick your signing Team (don't commit that change), then Run. A new device needs Developer Mode and may need your developer profile trusted.

## 3. Keychain recovery on a second device
**Status: BLOCKED until Seth confirms a second Apple device and the preconditions below.**

### Preconditions (all required)
| Seth confirms | Why |
|---|---|
| A second Apple device, same Apple Account, iCloud Keychain on | A restore on the same device doesn't prove sync |
| Which throwaway identity: the one created and backed up in the first device session, and that it really is a throwaway | It's the only throwaway backup on record. The backup was reported then and has not been re-checked |
| Its npub, from your notes | It's the PASS check. Don't open the primary iPhone to find it |
| It has at least one reflection saved to its account; note the date and keep what you need to recognize the text | Needed for the decrypt check |
| Device 2 has no Grateful Day account and no written entries | Guest entries on device 2 would be adopted by the restored account. If there are any, stop |

- No such backup: **BLOCKED, "no throwaway backup"**. Don't create one on device 2 and restore it there. Making one elsewhere without touching the primary would need a third device.
- No saved reflection, or no recorded npub: that criterion can't be tested, so the step can't PASS (record **INCONCLUSIVE**). Don't write anything on the primary to make it testable.

This step cannot re-test the act of making the backup. It tests that the earlier backup reaches device 2 and restores.

### Steps (device 2 only)
1. Install the build. Open **Settings > Account**. You should see **I've used Grateful Day before**, **Create a journal key** and **Use my Nostr account**. If an account already shows, stop and report. Screenshot.
2. Tap **I've used Grateful Day before**. Expect "Looking for your journal key backup…". **Never tap Create a journal key.** If "Make a new journal key?" appears, tap **I've used it before**.
3. One of:
   - "We found your journal key backup.": tap **Restore**.
   - Several rows, each only "Backup from <date>" (no account shown): pick the first-session date.
   - "Your backup hasn't arrived from iCloud yet…": wait 5 min, tap **Try again**; stop at 30 min and record INCONCLUSIVE. **Don't tap Use my Nostr account** (that is nsec import and doesn't test recovery). After **Back**, "Still looking for your journal key backup." on Today is expected.
   - "One backup couldn't be read…" may also appear. Record it; it is not a fail by itself.
4. Success is silent: the sheet just closes. If "What's private in your journal" appears, record it and tap **Not now**. That publishes nothing; reading the journal doesn't depend on it. It can come back on a later launch; tap **Not now** again.
5. **Settings > Account:** compare the shortened npub (first 12 characters, "…", last 6) with your recorded npub. No backup offer and no **Back up journal key** button are expected, because this identity already has a backup.
   - **Wrong identity** (for example C): stop. Report it. To back out, use **Sign out** only (it leaves the backup). Never Remove.
6. **Calendar:** keep the app open for a short while, then open the earlier reflection's date (if it's today, use Today). Don't edit anything.

### PASS / FAIL
| Criterion | PASS | FAIL |
|---|---|---|
| npub matches | Settings > Account matches the recorded npub | A different npub, including one nobody recognizes. If it's another known backup picked from a list, that's a wrong pick: report it, then ask before retrying |
| Earlier reflection decrypts | The earlier day appears and reads the same | "We can't open this day's reflection from your account on this iPhone…", wrong or garbled text, or no entry after the app has been reopened and 5 min have passed on a working network |
| No new key is created | npub matches; restore went only through **Restore**; no **Back up journal key** button | A new npub, a key made without being asked, or that button showing for this account |

Also FAIL: "Couldn't save the key." after **Restore**. Overall PASS needs all three rows.

**Evidence:** date/time, device 2 model and iOS version, build `c910134`, expected and restored npub, minutes until the backup was found, screenshots of steps 1, 3 and 5, and step 6 with text blurred.

## Next sequence, after recovery
Order set by Chief: 4 web → iOS, 5 deletion, 6 account switching, 7 VoiceOver.

**Identities for steps 4 to 6.** The app can't export a key, so an identity created in the app can't be used to log in on the web (unless its nsec is already held elsewhere). Make two new throwaways **outside the app**, **W1** and **W2**, in a password manager or Nostr tool, and note their npubs. Use them nowhere else.

**Where to run them.** Recommended: a new Simulator device created for this test, not signed in to an Apple Account, running `c910134`. Import with **Use my Nostr account > Continue > Use this account**; at the backup offer choose **Don't back up > Continue without backup**; at the publishing sheet tap **Continue**. The Simulator uses real relays, so these publish real (encrypted) throwaway events. Label evidence "simulator". Don't run while an automated simulator suite is running on the same Mac. Technically these three steps don't need the second device.

Web: one new private window per identity; close it before logging in as another. Keep entries **Private**. iOS reads from relays when the app is opened again: send it to the background (Simulator: Home) and reopen. There is no pull-to-refresh. After saving on iOS, stop typing, keep the app open about 30 s, and wait for the Saving mark to clear.

### 4. Web → iOS (W1)
**No relay edits on web before or during this step** (Audit L4, Chief 8a2523e2). A web relay edit is stored locally before its relay list is published. If that publish fails, web writes to relays iOS doesn't read. If a relay was already edited on web, stop and report before running the step.

1. Connect W1 on iOS. Don't write today on iOS yet.
2. Web as W1: write today's entry (test text "web one"), Private, save.
3. Reopen the iOS app.
- **PASS (a):** today's entry appears on iOS with identical text, readable, with no Saving mark.
4. Wait for iOS to be idle (no unsaved change). Web as W1: **replace** today's note with "web two" and save. Reopen the iOS app.
- **PASS (b):** iOS shows "web two"; Today shows "…was replaced by a version saved elsewhere. Your earlier text is in Set aside.", and Set aside contains "web one". (This is the archived-version check.)
- **FAIL:** entry missing after two reopens and 5 min; text differs or can't be opened; "web one" is not in Set aside; or an old version overwrites the newer one.
- If the entry never arrives, record the event id and which relays hold it before calling it a decryption failure.

### 5. Deletion (W1)
iOS can delete only today's reflection; past days are read-only there. Web can delete any of your own days. Don't dismiss or clear Set aside items.
- **5a, delete on iOS:** with today's entry synced, tap **Delete reflection > Delete**; keep the app open about 30 s. Then open a **new** private window as W1 and wait about 10 s.
  - **PASS:** the day is gone on iOS, and still gone in the new window and after reopening iOS.
  - **FAIL:** it comes back on iOS, or the new window still shows it after 5 min and one reload. First record whether any relay accepted the deletion and which still return the entry: deletion on Nostr is a request that a relay may ignore.
  - The iOS delete confirmation says "This can't be undone." Don't expect a Set aside copy of text deleted on this device.
- **5b, delete on web:** web as W1, write today again ("web three"), save, reopen iOS and confirm it arrived. Then web: **Delete entry > Request deletion**. Reopen iOS.
  - **PASS:** the day disappears on iOS and stays gone after another reopen, and on a new web window.
  - **FAIL:** the entry stays after two reopens and 5 min, or comes back later (including iOS publishing it again).
  - At `c910134`, a clean remote deletion keeps an internal copy that is **not shown** in Set aside. Its absence there is not a fail. Record what you see.
- Does not cover deleting a day that has unsaved edits on iOS (conflict testing).

### 6. Account switching (W1 = A, W2 = B), Simulator or spare device with `c910134`
Start on a fresh Simulator device (or confirm no ownerless days exist on the spare). W2 must have no entries. On a Simulator, "go offline" means turning off the Mac's network.

| # | Do | PASS | FAIL |
|---|---|---|---|
| 6.1 | Connect A and accept publishing. Let it finish syncing. Go offline. Write or change today ("A unsent"). **Settings > Account > Sign out** | Warning includes "1 reflection hasn't been saved to your account yet. It'll stay on this iPhone and will be saved when you sign back in to this account. It won't be saved to any other account." Take a screenshot, then **Sign out anyway** | Wrong count or wording, or no warning. A count above 1 is OK only if you can name each other unsent day |
| 6.2 | Go online. Import B, accept publishing, wait 1 min | B's editor doesn't contain "A unsent"; "You also wrote today under another account." appears, and the text opens read-only as "From another account". Web as B shows no entry. Web as A doesn't show "A unsent" | A's text is editable under B, shows as B's own, or is published as either account |
| 6.3 | Don't write as B. Sign out of B. Import A again, wait 1 min | A's text is there, saves, and web as A shows it. Web as B still shows nothing | Text lost or changed, doesn't save after 5 min, or appears under B |
| 6.4 | Sign out of A. **While signed out**, write today ("guest text"). Import B, wait 1 min | Guest text becomes B's (intended: the first account connected adopts guest writing) and web as B shows it. Web as A still shows "A unsent" only | Guest text is lost or published as A, or A's text appears under B |

At 6.4, if the app asks you to choose between versions or shows an unexpected sheet, screenshot it and report before choosing. If 6.1 shows a second paragraph about reflections written before sign-in, a guest day already existed: record it and restart on a fresh Simulator.

Covers iOS only. It is not a test of web account switching (#44 / #47).

### 7. VoiceOver
Needs a physical iPhone or iPad (the Simulator has no VoiceOver). Use device 2, or the primary iPhone **only if Seth chooses to**, navigating only: no writing, and don't activate Sign out, Remove, Delete or any account button.
Screens: Today, Calendar, one past day, Settings, Account, Privacy, Daily reminder. On a throwaway device also check the editor and the publishing sheet.

| Check | PASS | FAIL |
|---|---|---|
| Reach and activate | Every control on those screens (subject to the limit above) can be reached by swiping and has a spoken name; the three tabs are announced as tabs | A control is unreachable, unnamed or can't be activated, or focus gets trapped |
| Today order | Date, passage, author, question, editor | An order that hides or confuses the editor |
| Calendar | A day speaks its date, plus Today / Reflection written / Not saved to your account yet / Reflection from another account / Unavailable as they apply | A state conveyed only visually |
| Saving mark, if one is showing | "Not saved to your account yet" or equivalent; its detail can be opened | Silent or unreachable. If none shows: "not observed"; don't write on the primary to force it |

## Not covered by this sheet (still open)
Cross-device conflict resolution (needs two devices on one identity), Data Protection (lock state), background/foreground behavior, post-connect responsiveness (P53), web account switching beyond the earlier PR browser check.

## Results (steps 3 to 7)
| Step | Result | Date | Build / device | Evidence |
|---|---|---|---|---|
| 3 Keychain recovery | BLOCKED (awaiting Seth: device + preconditions) | | | |
| 4 Web → iOS | not run | | | |
| 5a Delete on iOS | not run | | | |
| 5b Delete on web | not run | | | |
| 6 Account switching | not run | | | |
| 7 VoiceOver | not run | | | |
