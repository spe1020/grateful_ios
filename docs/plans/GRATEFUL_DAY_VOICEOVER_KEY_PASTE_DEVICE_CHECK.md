---
title: "Grateful Day VoiceOver Key Paste Device Check"
tags: [grateful-day, ios, device-testing, accessibility, security]
status: active
created: 2026-11-25
---

**Seth runs this on a spare physical device. Not yet run. No Simulator result counts.** About 15 minutes. Requested by Chief (candidate defect **D4**). **Run it on its own, not combined with the other checks.**

**Why:** in the Simulator, with accessibility active under UI automation, Audit found a throwaway key's full nsec in the system log after an edit-menu **Paste** into the import field: process `GratefulDay`, category `AXRuntimeNotifications`, Info level, an announcement ending ", paste". The field is a secure field. Not confirmed on a device, with VoiceOver, or for the app's own **Paste** button.

## Read before running
- **This check may speak a private key aloud and write it to the device's system log and to Console on the Mac.** Only a disposable key makes that acceptable. Running it is your choice.
- **Use a new throwaway key made only for this check**, outside the app. Not your real key, and not one used in any other test. **Retire it afterwards:** never use it again, whatever the result.
- A spare iPhone or iPad with no Grateful Day account. **Not your primary iPhone.**
- **Never tap Use this account.**
- Run it alone, in private, with headphones. No screen recording or screenshots while the key is on the pasteboard or in Console.
- **Don't save, export, copy or send Console lines, and don't take a sysdiagnose.** Record only what the table asks for.
- Paste the key nowhere except the app's import field.

Build: `10ae4d6`; record the commit. A `git grep` of the app and package sources at `10ae4d6` for accessibility announcement calls finds none.

## Setup
1. Install the build. Open it from its icon, not from Xcode's debugger.
2. On the Mac, open **Console.app**, select the device, turn on **Action > Include Info Messages**, filter to process `GratefulDay` and category `AXRuntimeNotifications`, and start streaming.
3. On the device, set **Settings > Accessibility > Accessibility Shortcut** to VoiceOver, so a triple-click turns it on and off. Basics: tap selects, double-tap activates, swipe moves, a two-finger tap stops speech.
4. Turn VoiceOver on. Open Grateful Day: **Settings > Account > Use my Nostr account**.

**Edit-menu paste with VoiceOver:** select the field, double-tap and hold to open the edit menu, move to **Paste**, double-tap. If the menu won't open, set the rotor to **Edit**, swipe to **Paste** and double-tap. Record which route you used, and use the same one in A and B.

## A. Control, with a harmless word (no key)
1. Copy the word "banana" on the device.
2. Clear the Console window. Edit-menu paste it into the field.
3. Record what VoiceOver said and whether a Console line ending ", paste" appeared, and whether it showed the word, `<private>` or no text.
4. Tap **Cancel**, then open **Use my Nostr account** again.

If no line appears, check Console's settings and repeat once. If there's still none, go on and listen, but the log results are **INCONCLUSIVE**.

## B. Edit-menu paste, with the throwaway key
1. In a password manager **on the device**, copy the throwaway nsec.
2. Clear the Console window. Edit-menu paste into the empty field. Listen until speech stops. If it starts reading the key, that's enough: stop it with a two-finger tap.
3. Record: did the field fill; was any of the key's text spoken (don't count "bullet", "secure text field" or the word "paste"); and what the Console line showed: **key text**, **`<private>`**, **no text** or **no line**.
4. Watch for one more minute. Clear the Console window. Tap **Cancel**, then open **Use my Nostr account** again.

## C. The app's Paste button, with the same key
1. Copy the nsec again on the device.
2. Clear the Console window. Select the app's **Paste** button under the field and double-tap it once. If **Allow Paste** appears, record it and allow it.
3. Listen and watch as in B, and record the same things. Check every line shown, not only ones ending ", paste".
4. If the field doesn't fill, record **button didn't paste**. C then says nothing about announcements; it belongs to the Paste button check (D3, `GRATEFUL_DAY_IMPORT_PASTE_BUTTON_DEVICE_CHECK.md`). Don't use the edit menu instead.
5. Tap **Cancel**.

## Finish
Copy a harmless word. Stop Console streaming, clear its window and quit it. Turn VoiceOver off. Mark the key retired. Don't reset or erase the device; any other cleanup needs your own decision.

## Result (judge B and C separately)
| Result | When |
|---|---|
| **FAIL: D4** | In B or C, VoiceOver speaks any of the key's text, **or** Console shows any of it. Say which method and which of the two |
| **PASS** | The field filled, nothing from the key was spoken, the control showed that Console captures these announcements with their text readable, and Console showed no key text for this paste |
| **INCONCLUSIVE** | Nothing was spoken, but the log can't be judged: no control line, or text shown as `<private>` or missing. Also if you couldn't listen to the whole announcement. Record "not spoken" separately where that's true |
| **NOT TESTED** | The paste didn't fill the field |

- `<private>` doesn't show whether the key was or wasn't stored. Don't install a logging profile to reveal it.
- **If C also fails,** moving import to the app's button wouldn't fix D4 by itself. Report it that way.
- A pass covers only this device, iOS version, build and paste route.

## Record (physical device only)
| Step | Field filled? | Key spoken? | Console showed | Paste route / Allow Paste | Result |
|---|---|---|---|---|---|
| A control ("banana") | | word spoken? | | | n/a |
| B edit menu | | | | | not run |
| C app button | | | | | not run |

Also record the date, device model, iOS version, build, and that the key is retired. No nsec or any part of it, and no Console text.
