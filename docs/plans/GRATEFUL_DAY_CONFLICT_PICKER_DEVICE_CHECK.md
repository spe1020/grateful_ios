---
title: "Grateful Day Conflict and Deletion Picker One-Finger Device Check"
tags: [grateful-day, ios, device-testing, conflict]
status: active
created: 2026-11-25
---

**Seth runs this with one finger on a physical device. Not yet run. No Simulator result counts.** Companion to the other Phase 1 run sheets. Requested by Chief (decision log P104; updated for the D2 fix).

**Why:** defect **D2**, confirmed on iOS `10ae4d6` in the Simulator: a tap on any option selected the last one. On the two deletion screens the last option is the destructive one. This check confirms the fix with a finger on all three screens, plus two other buttons the same fix changes: **Show all** and **Keep both for all**. It doesn't replace the automated tests or Audit's review.

Build: the D2 fix, `fd67ebb` (draft PR #41, branch `fix/d2-conflict-picker`); record the commit. **Don't run this on `10ae4d6`.** If Chief names a newer #41 head, ask whether these steps still apply. `fd67ebb` is based on `10ae4d6` and doesn't include the D1 fix (#38). Screen text, layout and expected results were read from source at `fd67ebb`.

It also doesn't include the fix for **D5** (after another device deletes a day, writing it again on iOS shows a false "deleted from your account" conflict). Delete from the web only in screen B's steps. If a deletion screen or line appears anywhere these steps don't expect it, record it as possible D5, tap **Not now** and stop.

## Safety
- **Throwaway identity only. Never your real account.**
- **Not on your primary iPhone.** It would need an account switch.
- Use a physical iPhone or iPad with no Grateful Day account and no written entries. If it has either, stop.
- No **Remove account and local data**, no **Delete backup**, no app deletion or cleanup afterwards. The only deletions are the throwaway account's reflections, in the steps below.
- Don't add launch arguments when you run the build.
- Keep VoiceOver off. Pasting a key into the import field may put it in the device log (candidate D4, not confirmed on a device), so use this identity for nothing real and retire it afterwards.
- Made-up test lines only. Cover entry text in screenshots. Never screenshot or send the nsec.

## You need
- That device (iOS 17+), a Mac with Xcode to install the build (signing team `Z26TJQZZWC`; don't select the primary iPhone as the Run destination). Run `git fetch origin`, then check out `fd67ebb` in a separate worktree, confirm `git rev-parse --short HEAD`, and open the app from its icon.
- A **new** throwaway identity made outside the app, with its nsec in a password manager: the web needs it, and the app can't export a key yet. Note its npub.
- A computer with a private browser window on gratefulday.space, signed in as that identity. It must stay online while the device is offline.
- **Two calendar days.** Both apps only let you edit today, so Parts 1 and 2 must finish on one local date, and Part 4 needs a conflict from an earlier date plus one from a later date. Part 3 leaves the first one open; Part 4 runs on any later date. Allow about an hour on the first day, away from midnight, and 15 minutes on the later one. Don't change the device or computer clock. Keep the device and computer in the same time zone.
- To finish round 5's relay check: someone to query the relays by the throwaway's public npub (an agent can do this).

## Setup
1. Device: **Settings > Account > Use my Nostr account**, paste, **Continue**, check the npub, **Use this account**. At the backup offer: **Don't back up > Continue without backup**. At "What's private in your journal": **Continue**.
2. Write "base" on **Today**. Stop typing, keep the app open until the **Saving to your account** mark clears. Reload the web and confirm it shows "base".

## Part 1: both sides changed (rounds 1 to 3)

**Keep both for all** also appears on this screen. Don't tap it until Part 4.

### Make a conflict (before each round; N = 1, 2, 3)
1. The Saving mark is gone, and device and web show the same text.
2. Device: Airplane Mode on, with Wi-Fi off.
3. Device: replace today's text with "phone N".
4. Web: reload, replace today's note (don't add a second one) with "web N", keep it **Private**, save.
5. Device: Airplane Mode off, go to the Home Screen, reopen the app. Don't type.
6. Tap the line "Your reflection from <date> was also changed elsewhere. Choose what to keep." or "This reflection was also changed elsewhere. Both versions are kept on this iPhone."
7. Check that **Your account** shows "web N" and **This iPhone** shows "phone N". If they're swapped or wrong, that's a FAIL: screenshot, tap **Not now**, stop.

No conflict after two reopens and 5 minutes online: record BLOCKED. A conflict before step 3 is a separate finding (see D1, decision log P102): record it, tap **Not now**, stop.

### Hit-area probe (round 1, before tapping Done)
Each option is its own row. The options are **Keep both** (preselected), **Keep this iPhone's** and **Keep your account's**. The line under them changes with the selection:

| Selected | Line shown |
|---|---|
| Keep both | "Both texts stay on this day as separate notes, your account's first." |
| Keep this iPhone's | "Your account's text goes to Set aside." |
| Keep your account's | "This iPhone's text goes to Set aside." |

For each option, tap once near the **top** of its row, once in the **centre**, once near the **bottom**, staying inside the row. Before each tap, select a different option so you can see the change. Record where the checkmark lands after every tap. Don't tap **Done** during the probe.

| Tapped | Top → selected | Centre → selected | Bottom → selected |
|---|---|---|---|
| Keep both | | | |
| Keep this iPhone's | | | |
| Keep your account's | | | |

If any tap selects another option or doesn't select the one tapped, that's a **FAIL**: screenshot or screen-record it (text covered), tap **Not now** and stop.

### Rounds 1 to 3: apply each option once
In each round, first make sure a **different** option is selected, then tap the target **once, in the centre**. Note the checkmark and line, then tap **Done**. Keep the app open until the Saving mark clears (if one shows), then reload the web.

To open Set aside: on **Today**, tap "An earlier version of this reflection is in Set aside." Items from earlier rounds stay there; the newest is first.

| Round | Tap | Today on device | Set aside | Web after reload |
|---|---|---|---|---|
| 1 | Keep this iPhone's | "phone 1" | New: "web 1", with "You kept the other version of this day." | "phone 1" |
| 2 | Keep your account's | "web 2" | New: "phone 2", same reason | "web 2" |
| 3 | Keep both | "web 3" then "phone 3", as separate notes | **No new item** | Both, "web 3" first |

Between rounds, repeat **Make a conflict**.

## Part 2: the two deletion screens (rounds 4 to 7)
Each screen has two options. The first is preselected and is the one that keeps the text; the second is destructive. **Keep both for all** shouldn't appear.

### Make the conflict
Before **each** round: the device and a freshly reloaded web page both show the same synced reflection, with no Saving mark. If today is empty (after rounds 5 and 7), write "base N" on the device, wait until the mark clears, and confirm it on the web. N is the round number.

**Screen A, deleted on this iPhone but changed on the account (rounds 4 and 5):**
1. Device: Airplane Mode on, Wi-Fi off.
2. Device: **Today > Delete reflection > Delete** (the confirmation reads "Delete this reflection? This can't be undone.").
3. Web: reload, replace today's note with "web N", keep it **Private**, save.
4. Device: Airplane Mode off, Home Screen, reopen. Don't type.
5. Open the conflict from the line "You deleted this day here, but it was changed in your account. Choose what to keep." (or the "…was also changed elsewhere. Choose what to keep." line).
6. Check: the heading is "You deleted <date> here, but it was changed in your account.", **Your account** shows "web N", and **This iPhone** shows "You deleted this day here."

**Screen B, deleted on the account but changed on this iPhone (rounds 6 and 7):**
1. Device: Airplane Mode on, Wi-Fi off. Replace today's text with "phone N".
2. Web: reload, then **Delete entry > Request deletion**. The web may say "Failed to request deletion" even though a relay accepted it: record the message, then open a **new** private window as the throwaway to see whether the entry is gone. If it still shows, wait 2 minutes and check again. Still there: record BLOCKED.
3. Device: Airplane Mode off, Home Screen, reopen. Don't type.
4. Open the conflict from "This day was deleted from your account. What you wrote here is kept on this iPhone." (or the "…was also changed elsewhere. Choose what to keep." line).
5. Check: the heading is "<date> was deleted from your account, but you changed it on this iPhone.", **Your account** shows "This day was deleted from your account.", and **This iPhone** shows "phone N".

A wrong heading or text: screenshot, **Not now**, stop. No conflict after two reopens and 5 minutes online: BLOCKED.

### Probe each screen before Done (rounds 4 and 6)
Tap both options near the top, centre and bottom of each row, selecting the other option before each tap. Don't tap **Done** during the probe. Any tap that doesn't select the option tapped is a **FAIL**: screenshot, **Not now**, stop. Include the preselected option: tapping it to confirm must leave it selected.

| Screen | Option tapped | Line shown when selected | Top → selected | Centre → selected | Bottom → selected |
|---|---|---|---|---|---|
| A | Keep your account's | "This day comes back on this iPhone with your account's text." | | | |
| A | Delete it everywhere | "Your account's text goes to Set aside on this iPhone, and this day is deleted from your account." | | | |
| B | Keep this iPhone's | "This day goes back to your account with what you wrote here." | | | |
| B | Let it stay deleted | "What you wrote here goes to Set aside, and this day is removed from this iPhone." | | | |

### Apply each option once
Select the **other** option first, then tap the target once in the centre, check the checkmark and line, and tap **Done**. Keep the app open and online for at least 2 minutes, and until any Saving mark clears. Then check a **new** private window as the throwaway (wait about 10 s after it loads).

| Round | Screen: tap | Device after Done | Set aside | Web, new private window |
|---|---|---|---|---|
| 4 | A: Keep your account's | Today shows "web 4" | **No new item** | "web 4" |
| 5 | A: Delete it everywhere | Today is empty | New: "web 5", with "You deleted this day here." | No entry for today, **and** the relay check below |
| 6 | B: Keep this iPhone's | Today shows "phone 6" | **No new item** | "phone 6" |
| 7 | B: Let it stay deleted | Today is empty | New: "phone 7", with "This day was deleted from your account." | No entry for today |

For rounds 4 to 7, also close and reopen the app once: the result must not change, and the same conflict must not return. Open Set aside from "An earlier version of this reflection is in Set aside." on **Today**.

### Relay check for round 5 (Delete it everywhere)
An empty web page alone doesn't show that the deletion reached the relays. **Right after round 5's web check, before writing "base 6"**, note the time, today's date and the throwaway npub, and have the relays queried (public data only; no key needed). Record:
- the deletion event (kind 5) for this day's address, signed by the throwaway, **newer than "web 5"**: its event ID;
- which of the account's write relays hold it (with the app's defaults: `relay.damus.io`, `nos.lol`, `relay.primal.net`);
- which relays still return the "web 5" entry.

**Relay PASS:** that deletion is on at least 2 of the account's write relays (all of them if it has only one). A relay still returning the old entry is recorded, not a failure by itself: deletion on Nostr is a request. **Relay FAIL:** after 10 minutes online with the app open, no relay holds such a deletion. Only one relay, or a lookup that couldn't be done: **PENDING**, and round 5 can't be recorded as PASS. Finishing the lookup later is fine, but relays can then also hold later events: match on the time and ID order.

## Part 3: Show all (same date, after Part 2)
**Show all** appears under a long text. Both long texts and their buttons sit in one list row, so each button must expand only its own text.

1. Today is empty after round 7: write "base long" on the device, wait for the Saving mark to clear, and confirm it on the web.
2. Make a conflict with the Part 1 steps, but replace today's text with **ten short lines**, one per line with no blank lines: "phone line 1" to "phone line 10" on the device, and "web line 1" to "web line 10" on the web.
3. Open the conflict. Both texts should be cut off, each with its own **Show all** underneath. If not, record BLOCKED.
4. **Taps that must do nothing:** tap once on the **Your account** label, on its text, on the **This iPhone** label, on its text, and on the blank space beside each **Show all** (same height, well clear of the words). After each tap: neither text expands, the selected option is unchanged and the screen stays open. Tap, don't long-press (a long press selects text).
5. Tap the words of the **first Show all** (under Your account). **Only** "web line 10" and the rest of that text appear; This iPhone stays cut off with its button.
6. Tap **Not now**, then reopen the conflict. Both are cut off again. If they aren't, record that and don't judge step 7.
7. Tap the words of the **second Show all** (under This iPhone). **Only** that text expands.
8. Tap **Not now**. **Don't resolve this conflict:** it's the first day for Part 4. Note its date.

| Check | PASS |
|---|---|
| Step 4, six taps | Nothing expands or changes |
| First Show all | Only Your account expands |
| Second Show all | Only This iPhone expands |

## Part 4: Keep both for all (a later date)
1. Open the app online. The Part 3 conflict should still be open (the Today line, or that date in **Calendar**). If it's gone and you didn't resolve it, that's a finding: record it and stop.
2. Write "base two" on **Today**, wait until today's Saving mark clears, and confirm it on the web.
3. Make a conflict for today with the Part 1 steps, using "phone two" and "web two".
4. Open the conflict. Both dates should be listed, under "You wrote on 2 days in both places." (or "2 reflections were also changed elsewhere."), with **Keep both for all** near the top. Only one date: record BLOCKED.
5. Before testing, note how many Set aside items each of the two dates has (open the date in **Calendar**; use its Set aside line if there is one, otherwise 0). Return to the conflict.
6. Select a non-default option for each day: **Keep this iPhone's** for the earlier date and **Keep your account's** for today.
7. **Taps that must do nothing:** tap once on the heading, on the line "Choose what to keep for each day. Any text you don't keep goes to Set aside on this iPhone.", on the blank space beside **Keep both for all** (same height, well clear of the words), just above and just below its words, and on each day's date and texts. After each tap: the screen stays open, both days are still listed and both selections are unchanged. If the screen closes or a day disappears, that's a **FAIL**: stop and record what the app shows.
8. Tap the words **Keep both for all** once. It's meant to apply **Keep both** to both days, replacing the selections from step 6.

| Check after step 8 | PASS |
|---|---|
| Screen | Closes. Today shows "Kept both versions on 2 days." |
| Earlier date on device | The ten web lines, then the ten phone lines, as separate notes |
| Today on device | "web two", then "phone two", as separate notes |
| Set aside | **No new item** on either date (compare with step 5) |
| Web, new private window, after the app has been open and online for 2 minutes | Both dates show both texts, web text first |

Close and reopen the app once: both results stay and neither conflict returns.

## PASS / FAIL
- **PASS:** every probe tap in rounds 1, 4 and 6 selects the option tapped; all seven rounds give the results in their tables; round 5's relay check passes; and every Part 3 and Part 4 check passes.
- **FAIL, selection:** any tap inside an option's row doesn't select that option.
- **FAIL, button isolation:** a tap anywhere other than a button's own words expands a text, applies **Keep both for all** or changes a selection; or one **Show all** expands the other text. A tap right at the edge of the words is inconclusive: repeat it farther away. A button that doesn't work when its words are tapped is also a FAIL.
- **FAIL, result:** the right option shows as selected, but the device, Set aside, web or relay result differs. Also fail if text that should be kept or set aside is in neither place, or if a deletion happens that wasn't chosen. Stop and leave the device as it is.
- **INCONCLUSIVE:** a tap may have landed outside the row or between two rows and you can't repeat it, or the web couldn't be checked.
- **BLOCKED:** a prerequisite is missing or a required conflict doesn't appear.
- **PENDING:** everything run so far passed, but round 5's relay check or Part 4 isn't finished.

Record each screen's and button's result separately, so one screen's failure doesn't hide what passed.

Not covered: more than two conflicting days, **Keep both for all** across mixed screen types or public reflections, the "Can't compare these yet" section (including its **Show all**), VoiceOver.

## Result record (physical device only)
| Date | Device / iOS | Build | Overall | Evidence |
|---|---|---|---|---|
| | | | not run | |

| Part | Probe | Rounds | Result |
|---|---|---|---|
| Both changed | | 1: 2: 3: | not run |
| A: deleted here | | 4: 5: | not run |
| B: deleted from account | | 6: 7: | not run |
| Show all (Part 3) | Do-nothing taps: | First: Second: | not run |
| Keep both for all (Part 4, date: ) | Do-nothing taps: | Applied result: | not run |
| Round 5 relay check | Event ID: | Relays holding it: / still returning "web 5": | not run |

Send back both tables and the probe tables, screenshots (text covered), the device model, iOS version, build and throwaway npub. No nsec, no reflection text.
