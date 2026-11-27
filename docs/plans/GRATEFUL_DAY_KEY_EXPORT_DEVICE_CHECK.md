---
title: "Grateful Day Journal Key Export Device Check"
tags: [grateful-day, ios, device-testing, key-export, security]
status: draft
created: 2026-11-25
---

**Seth runs this on a spare physical device. Not yet run. No Simulator result counts.** About 45 minutes. Requested by Chief. Covers the device-only parts of key export r3 §1.7, plus Audit's screen-mirroring item.

> ## ⚠ Not ready to run: no build is named yet
> Seth ruled B option 1 (8a3b1c2b): the app no longer clears the clipboard on hide; the 60 s expiry is the only clearing.
> - **Build:** the export commit Chief names **after** Audit's check of the change. Record it here: `________`. **Don't run this on `cfd6097`** (draft PR #40): it still clears the clipboard on hide, so check A would fail.

Screen text and behaviour were read from source at `cfd6097`; the clipboard steps describe that code **without** its clear-on-hide function. Recheck against the named build.

## Safety
- **These steps copy, show and paste a real private key, so use only a new throwaway.** Never your real key. Create it in the app (below), use it for nothing else, and **retire it afterwards.**
- **A spare device. Never your primary iPhone.**
- **Keep VoiceOver off** (see the separate VoiceOver check, candidate D4).
- At the backup offer choose **Don't back up**, so the key isn't put in iCloud Keychain.
- Paste the key **only** into the secret-key login field of the other Nostr client. Never into Notes, Messages, a search or address bar, or a document, on any device.
- Never send, upload or attach the key, a screenshot or a recording of it. No photos of the key. Evidence is your written observations.
- On the Mac, **quit any clipboard manager**: it could keep a copy.
- Checks F and G can save the key into **Photos**. Use a device with **iCloud Photos off**; if you can't, the image or video may sync to your other devices, and you may skip F's screenshot or G (record SKIPPED).
- No **Remove account and local data**, no **Delete backup**, no reset.

## You need
1. A spare iPhone or iPad, iOS 17+, **with a passcode**, with no Grateful Day account or written entries. If it has either, stop.
2. Install the named build from Xcode (team `Z26TJQZZWC`; never select the primary iPhone as the Run destination). Record `git rev-parse --short HEAD`. Open it from its icon.
3. **Another Nostr client** (not Grateful Day for iPhone) on the same device that logs in with an nsec and shows the npub. A native app is best; record its name and version. It receives the throwaway key and may publish things as that identity.
4. A Mac for check C, signed in to the **same Apple Account** as the device, with Wi-Fi and Bluetooth on and **Handoff** on for both.
5. For check G, a screen-mirroring target in Control Center, such as an Apple TV or a Mac with AirPlay Receiver on.
6. A timer on another device or watch. Set the spare's **Auto-Lock to 5 minutes or Never** and note the old value, so locking doesn't stand in for the app's own timeout.

## Setup
1. **Settings > Account > Create a journal key > Make a new key.** At the backup offer: **Don't back up > Continue without backup.** At "What's private in your journal": **Continue**.
2. Write a made-up reflection on **Today** and wait for the Saving mark to clear.
3. **Settings > Account:** note the shortened npub (first 12 characters, "…", last 6). Under **Advanced**, tap **Use your journal key in another app**. Check Screen 1 is headed "Your journal key is your account". If the row is missing, record FAIL and stop.

**Opening Screen 3** (used below): from Screen 1 tap **Show journal key** and pass the device prompt ("Confirm it's you to show your journal key." where iOS shows the reason). Screen 3 shows the account and dots. **Every time you return to Screen 1, opening Screen 3 must ask you to authenticate again.** If it ever opens without asking, that's a FAIL: record which check came before it.

## A. Copy, switch apps, log in elsewhere
1. Open Screen 3. **Don't tap Show.** Tap **Copy journal key**. Start the timer. You should see "Copied. It will be cleared from the clipboard in 1 minute. Paste it now."
2. Within 45 seconds, switch to the other client and paste into its secret-key field. Log in.
3. Compare the npub it shows with the account line on Screen 3.
4. Return to Grateful Day: it should be on Screen 1.
- **PASS:** the paste fills the field after switching apps, and the other client shows the **same npub**.
- **FAIL:** nothing to paste within 45 seconds, a different npub, or login rejects the pasted text.

**A2, web decryption:** in a private browser window on gratefulday.space, log in with the same key (open Screen 3, **Copy journal key**, paste into the site's key field within 45 seconds). The site keeps the key in browser storage, so **when A2 is done, log out and then close that private window.** **PASS:** same account, and the Setup reflection appears and reads the same. If the site offers no key field, record BLOCKED.

## B. The clipboard after 60 seconds
First, in the other client, return to its empty secret-key login field (log out of the throwaway if you need to).
1. **Expiry:** open Screen 3, **Copy journal key**, start the timer, switch to the other client and **don't paste** until **75 seconds**. Long-press the empty field.
   - No **Paste** offered: PASS. If **Paste** is offered, tap it: the field stays empty: PASS; the field fills with hidden characters or the key: **FAIL** (don't log in; clear the field).
2. **A newer copy survives:** have two things ready: a web page on the device that shows the word "banana" (any search result or article; copying it must not mean typing or saving it anywhere), and the other client's **empty** secret-key login field. Copy the key in Grateful Day and start the timer. Within 15 seconds, select and copy "banana" on that page. Return to Grateful Day, then go to the Home Screen. At 75 seconds from the key copy, go to the other client's empty secret-key field, long-press and tap **Paste**. **Paste nowhere else**, and don't log in. The field may hide what it shows: use its reveal control only if the content is short enough to be "banana" (6 characters). Never reveal anything longer.
   - **PASS:** "banana" fills the field.
   - **FAIL:** the key, or long hidden text, fills it. Don't reveal it or log in; clear the field.
   - **FAIL:** **Paste** isn't offered, or nothing is pasted: the newer copy was wiped.
   - **INCONCLUSIVE:** the field masks its text and you can't tell six characters from anything else. Clear it.
   - Clear the field afterwards.

If A didn't pass, B1 proves nothing: record INCONCLUSIVE.

## C. Universal Clipboard is blocked
The Mac command below prints only a count. **It never displays the clipboard.** Don't paste into any Mac app.
1. **Control:** on the device, copy the word "banana" normally (select and Copy). Within a minute, on the Mac, in Terminal run `pbpaste | grep -c '^banana$'`. It must print `1`. If it prints `0` after a few tries, Universal Clipboard isn't working: record **INCONCLUSIVE** and don't judge C.
2. On the Mac, copy the word "mango" (this replaces "banana").
3. Device: open Screen 3, **Copy journal key**. Keep the device unlocked and near the Mac.
4. On the Mac, run `pbpaste | grep -c '^nsec1'` at about 5, 20 and 45 seconds.
5. **Control again:** on the device, copy "kiwi" normally; within a minute `pbpaste | grep -c '^kiwi$'` on the Mac must print `1`.
- **PASS:** all three key checks print `0`, and both controls print `1`.
- **FAIL:** any key check prints `1`. Then copy a harmless word on the Mac to replace it.
- **INCONCLUSIVE:** either control doesn't print `1`.

## D. Each way of leaving hides the key
For each row: open Screen 3, tap **Show** (the key appears in groups of 4), do the action, then come back.

| # | Action | PASS |
|---|---|---|
| D1 | Go to the Home Screen, wait 5 s, reopen | Back on Screen 1; no key |
| D2 | Open the app switcher (swipe up and hold). Look at Grateful Day's card, then return to the app | The card shows a plain cover, **never the key**; back on Screen 1 |
| D3 | Tap **Done** | The export flow closes to **Account**; no key |
| D4 | Use the navigation **Back** button | Back on Screen 1; no key |

After each, open Screen 3 again: it must ask for authentication and show dots. (After D3, enter from **Advanced** again.) **FAIL:** the key is still on screen or on the app-switcher card, or Screen 3 reopens without authentication. A brief flash of the key on the card or while returning counts: record it.

## E. Two-minute timeout
1. Open Screen 3 and start the timer **when Screen 3 appears** (the timeout runs from then, not from **Show**). Tap **Show**.
2. Don't touch or move away from the app. Check at 1:40, then watch until 2:30.
- **PASS:** the key is still shown at 1:40, and between about 1:55 and 2:15 the app returns to Screen 1 by itself. Opening Screen 3 asks for authentication again.
- **FAIL:** it hides before 1:40, or is still shown at 2:30.
- **INCONCLUSIVE:** the device dimmed to lock, a notification or call interrupted, or you touched another app.

## F. Screenshot notice
1. Open Screen 3. With the key **hidden** (dots), take a screenshot. **Expected:** no notice.
2. Tap **Show**, then take one screenshot. **Expected:** "Your screenshot includes your journal key. Delete it from Photos, and from Recently Deleted." The key stays usable; nothing blocks the screen.
- **PASS:** both as expected. **FAIL:** no notice for the second, or a notice for the first.
- Afterwards, do what the notice says with the **second** screenshot: delete it from Photos and from Recently Deleted. Don't use it as evidence.

## G. Screen mirroring and recording
Opening Control Center makes the app inactive, which should already hide the key. So after you come back you're likely to find **Screen 1**. That's fine. What must never happen is the key shown in the clear while the screen is mirrored or recorded.

**G1, mirroring started while Screen 3 is open** (Audit's item):
1. Open Screen 3 and tap **Show**.
2. Open Control Center, start **Screen Mirroring** to the target, and close Control Center. Watch both screens.
3. Record where the app is: **Screen 1**, or **Screen 3**. If it's Screen 3, it must show **dots**.
4. With mirroring still on, open Screen 3 (again if needed). **Expected:** dots, **Show** is disabled, and "Your screen is being recorded or shared, so your key is hidden."
5. Tap **Copy journal key**: the copied confirmation appears (don't paste).
6. Stop mirroring. If the app is on Screen 1, open Screen 3: **Show** works again.
- **PASS:** after mirroring starts, the key never appears on the device or the target; step 3 is Screen 1 or dots; steps 4 to 6 as expected.
- **FAIL:** the readable key appears on either screen while mirroring is on, or **Show** works while it's on.
- A Control Center transition frame on the target that shows the key also counts: record it. No mirroring target: BLOCKED.

**G2, screen recording** (§1.7): the same steps with **Screen Recording** in place of mirroring. Expected results are the same. Play the recording back **on the device only**: the key must never be readable after recording starts. Then delete that video from Photos and Recently Deleted. Don't use it as evidence.

## Finish
Copy a harmless word on the device and on the Mac. Log the throwaway out of the other client. For any browser where you used the key, log out **and close the private window**. Restore Auto-Lock. Mark the key **retired**. Leave Grateful Day's test account in place; any further cleanup needs your own decision.

The other client may have published a profile (kind 0) or a relay list (kind 10002) for the throwaway. A relay list would change which relays Grateful Day uses for that identity. It doesn't affect these checks, but **don't treat this identity as a clean default-relay account in any later test.** Record the client's name with that note.

## Results
Each check is **PASS**, **FAIL**, **INCONCLUSIVE**, **BLOCKED** or **SKIPPED**. The sheet passes only if every check passes. A skipped or blocked check leaves that §1.7 item open. Stop the run if the key ends up anywhere these steps don't put it, and record where.

| Check | Result | What you saw (no key text) |
|---|---|---|
| Setup: Advanced row and Screen 1 | not run | |
| Authentication asked on every reopen | not run | |
| A same npub in another client | not run | |
| A2 web decryption | not run | |
| B1 empty after 60 s | not run | |
| B2 newer copy survives | not run | |
| C Universal Clipboard blocked (controls: ) | not run | |
| D1 Home Screen | not run | |
| D2 app switcher | not run | |
| D3 Done | not run | |
| D4 Back | not run | |
| E 2-minute timeout (hid at: ) | not run | |
| F screenshot notice | not run | |
| G1 mirroring (app was on: ) | not run | |
| G2 recording | not run | |

Record the date, device model, iOS version, Mac OS version, build commit, other client and version, and that the key is retired. A shortened npub is fine. **No nsec or part of it.**

**Not covered:** §1.7's VoiceOver and largest-text-size item (it needs the accessibility checklist, and VoiceOver reads the key aloud by design), the no-passcode message, and cancelled or failed authentication. Key-mismatch handling is covered by tests, not here.
