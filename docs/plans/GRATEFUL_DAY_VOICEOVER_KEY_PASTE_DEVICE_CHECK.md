---
title: "Grateful Day VoiceOver Key Paste Device Check"
tags: [grateful-day, ios, device-testing, accessibility, security]
status: active
created: 2026-11-25
---

**Seth runs this on a spare physical device. Not yet run. No Simulator result counts.** About 15 minutes. Requested by Chief (candidate defect **D4**). **Run it on its own, not combined with the other checks.**

Approved by Seth (L, 8a3b1c2b). **No result from this check shows the key is safe.** A negative result is inconclusive.

**Why:** in the Simulator, with accessibility active under UI automation, Audit found a throwaway key's full nsec in the system log after an edit-menu **Paste** into the import field: process `GratefulDay`, category `AXRuntimeNotifications`, Info level, an announcement ending ", paste". The field is a secure field. Not confirmed on a device, with VoiceOver, or for the app's own **Paste** button.

## Read before running
- **This check may speak a private key aloud and write it to the device's system log and to Console on the Mac.** Only a disposable key makes that acceptable. Running it is your choice.
- **Use a new throwaway key made only for this check**, outside the app. Not your real key, and not one used in any other test. **Retire it afterwards:** never use it again, whatever the result.
- A spare iPhone or iPad with no Grateful Day account. **Not your primary iPhone.**
- **Never tap Use this account.**
- Run it alone, in private, with headphones. No screen recording or screenshots while the key is on the pasteboard or in Console.
- **Don't save, export, copy or send Console lines, and don't take a sysdiagnose.** Record only what the table asks for.
- Paste the key nowhere except the app's import field.

Build: `a254289`; record the commit. A `git grep` of `App/GratefulDay` and `Sources` at `a254289` finds one accessibility announcement call, in key export (`Account/KeyExport.swift`, added by #40): it announces the "Copied" notice after **Copy journal key**, not the key. This check doesn't use key export. The import screen and its Paste button code didn't change between `f040127` and `a254289`.

## Setup
1. Install the build. Open it from its icon, not from Xcode's debugger.
2. On the Mac, open **Console.app**, select the device, turn on **Action > Include Info Messages**, and start streaming with **no process or category filter**. With real VoiceOver, another process may log the announcement, so don't assume it's the one seen in the Simulator. **Never type the key, or any part of it, into Console's search box.**
3. On the device, set **Settings > Accessibility > Accessibility Shortcut** to VoiceOver, so a triple-click turns it on and off. Basics: tap selects, double-tap activates, swipe moves, a two-finger tap stops speech.
4. Turn VoiceOver on. Open Grateful Day: **Settings > Account > Use my Nostr account**.

**Edit-menu paste with VoiceOver:** select the field, double-tap and hold to open the edit menu, move to **Paste**, double-tap. If the menu won't open, set the rotor to **Edit**, swipe to **Paste** and double-tap. Record which route you used, and use the same one in A and B.

## A. Control, with a harmless word (no key)
1. Copy the word "banana" on the device.
2. Clear the Console window. Edit-menu paste it into the field.
3. Record what VoiceOver said. Once speech stops, pause Console and search the **message text** for `banana`, still with no process or category filter.
4. For **every** line from this paste that shows it, write down the process and category (show those columns, or select the line). List **each different pair** in the record table. Check the whole list of results, not only the first line or lines ending ", paste".
5. Clear the search, resume streaming, tap **Cancel**, then open **Use my Nostr account** again.

If the search finds nothing, check Console's settings and repeat once. If there's still nothing, go on and listen, but the log results are **INCONCLUSIVE**.

## B. Edit-menu paste, with the throwaway key
1. In a password manager **on the device**, copy the throwaway nsec.
2. Clear the Console window. Edit-menu paste into the empty field. Listen until speech stops. If it starts reading the key, that's enough: stop it with a two-finger tap.
3. Record: did the field fill, and was any of the key's text spoken (don't count "bullet", "secure text field" or the word "paste"). Then pause Console. For **each process and category pair recorded in A**, one at a time, filter to exactly that pair, with no message-text search. Read the lines from this paste and record for each pair: **key text**, **`<private>`**, **no text** or **no line**. Remove the filter before the next pair.
4. Resume streaming and watch for one more minute, then check each pair again. Clear the Console window. Tap **Cancel**, then open **Use my Nostr account** again.

## C. The app's Paste button, with the same key
1. Copy the nsec again on the device.
2. Clear the Console window. Select the app's **Paste** button under the field and double-tap it once. If **Allow Paste** appears, record it and allow it.
3. Listen as in B, then check Console in the same way: every pair from A, one at a time, including B's extra minute. Check every line from this paste, not only ones ending ", paste".
4. If the field doesn't fill, record **button didn't paste**. C then says nothing about announcements; it belongs to the Paste button check (D3, `GRATEFUL_DAY_IMPORT_PASTE_BUTTON_DEVICE_CHECK.md`). Don't use the edit menu instead.
5. Tap **Cancel**.

## Finish
Copy a harmless word. Stop Console streaming, clear its window and quit it. Turn VoiceOver off. Mark the key retired. Don't reset or erase the device; any other cleanup needs your own decision.

## Result (judge B and C separately)
| Result | When |
|---|---|
| **FAIL: D4** | In B or C, VoiceOver speaks any of the key's text, **or** Console shows any of it. Say which method and which of the two |
| **NOT REPRODUCED** | The field filled, nothing from the key was spoken, A found at least one line with "banana" readable, **every** pair from A was checked for this paste with readable announcement text, and none showed key text. Per Seth's L ruling (8a3b1c2b), this doesn't show the key is safe. D4 stays open |
| **INCONCLUSIVE** | Nothing was spoken, but the log can't be judged: A found no "banana" line, or for any pair from A the text is `<private>` or missing, the line is absent, or the pair wasn't checked. Also if you couldn't listen to the whole announcement. Record "not spoken" separately where that's true |
| **NOT TESTED** | The paste didn't fill the field |

- `<private>` doesn't show whether the key was or wasn't stored. Don't install a logging profile to reveal it.
- **If C also fails,** moving import to the app's button wouldn't fix D4 by itself. Report it that way.
- A NOT REPRODUCED result covers only this device, iOS version, build and paste route, **and only the processes and categories A found**. It doesn't show the key was logged nowhere else.

## Record (physical device only)
**Pairs found in A** (names only, no message text):

| # | Process | Category |
|---|---|---|
| 1 | | |
| 2 | | |
| 3 (add rows as needed) | | |

| Step | Field filled? | Key spoken? | Console showed, for each pair # | Paste route / Allow Paste | Result |
|---|---|---|---|---|---|
| A control ("banana") | | word spoken? | | | n/a |
| B edit menu | | | | | not run |
| C app button | | | | | not run |

Also record the date, device model, iOS version, build, and that the key is retired. No nsec or any part of it, and no Console text.
