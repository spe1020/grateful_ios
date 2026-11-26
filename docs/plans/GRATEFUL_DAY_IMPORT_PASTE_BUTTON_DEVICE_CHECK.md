---
title: "Grateful Day Import Paste Button Device Check"
tags: [grateful-day, ios, device-testing, import]
status: active
created: 2026-11-25
---

**Seth runs this on a spare physical device. Not yet run. No Simulator result counts.** About 5 minutes. Requested by Chief.

**Why:** Sous reports that in the Simulator, the import screen's own **Paste** button never filled the field and never showed **Allow Paste**, while the system edit menu's **Paste** worked from the same pasteboard. If the button also fails on a device, it's a real import defect (**D3**). If it works there, record a Simulator-only behaviour.

Build: `10ae4d6`; record the commit. Read from source at `10ae4d6`: the button reads the pasteboard once. If it gets text, it fills the field and then clears the pasteboard, unless something newer was copied during the read. If it gets nothing, it changes nothing and shows no error.

## Safety
- **Run this whole check with VoiceOver off**, and don't combine it with the VoiceOver check. Audit saw the edit-menu **Paste** announce and log a full throwaway key in the Simulator with accessibility active under UI automation. VoiceOver off hasn't been shown to prevent that on a device, so **retire the key afterwards** and never use it for anything real. The VoiceOver risk (candidate D4) has its own sheet, `GRATEFUL_DAY_VOICEOVER_KEY_PASTE_DEVICE_CHECK.md`.
- **A throwaway key made outside the app only. Never your real key.**
- A spare iPhone or iPad with no Grateful Day account. **Not your primary iPhone.**
- **Never tap Use this account.** This check saves no key.
- **Never paste the key anywhere except the app's import field** (not Notes, Safari or Messages, even to test whether the pasteboard is empty).
- Don't screenshot or record the password manager or the key.
- If you also run the conflict picker check (`GRATEFUL_DAY_CONFLICT_PICKER_DEVICE_CHECK.md`), run this first, on the same device.

## Steps
1. In a password manager **on that device**, copy the throwaway nsec. Don't copy it on a Mac or another device. Know its npub. If the password manager clears the clipboard on a timer, do steps 2 to 5 before it does.
2. Open Grateful Day: **Settings > Account > Use my Nostr account**.
3. Tap the app's **Paste** button under the field, once. Don't use the long-press menu yet.
4. Record whether **Allow Paste** appeared. If it did, tap **Allow Paste**. If it didn't, check whether **Settings > Apps > Grateful Day > Paste from Other Apps** exists (the path varies by iOS version) and record its value.
5. Record whether the field filled (it shows dots). If it did, tap **Continue** and check that "This is the account <npub>." shows the throwaway's npub. **Don't tap Use this account.** Tap **Cancel**.

### If the field filled: is the pasteboard empty?
6. Open **Use my Nostr account** again (the field starts empty). Without copying anything, long-press the field.
   - No **Paste** in the menu: record **empty**.
   - **Paste** is offered: tap it. Field stays empty: **empty**. Field fills: **not empty**.
7. Tap **Cancel**.

### If the field didn't fill: control
6. Without copying again, long-press the same field and choose the system **Paste**.
7. **If it fills:** tap **Continue**, check the npub, then **Cancel**. This shows the key was still on the pasteboard after the button failed. Repeat once from step 1 with a fresh copy.
8. **If it doesn't fill (key-consumed check):** tap **Cancel**. Make a **fresh copy** in the password manager, open **Use my Nostr account** again, and **don't touch the app's Paste button**. Long-press the field and choose the system **Paste** first.
   - It fills: tap **Continue**, check the npub, then **Cancel**. The system Paste works from a fresh copy but found nothing after the button tap: **FAIL: D3 (key consumed)**, meaning the button used up the key without filling the field. If the first copy may have expired on a timer, record INCONCLUSIVE and repeat from step 1 within the time limit.
   - It still doesn't fill: **INCONCLUSIVE**. Tap **Cancel**.

**At the end:** copy any harmless word, so the key doesn't stay on the pasteboard. No other cleanup.

## Result
| Result | When |
|---|---|
| **PASS** (Simulator-only behaviour) | The button fills the field (after **Allow Paste**, if asked), the npub matches, and the pasteboard is empty afterwards. A missing prompt alone isn't a failure: record the Paste from Other Apps setting |
| **FAIL: D3** | In both attempts, the button doesn't fill the field although you didn't deny the paste, and the system **Paste** then works from the same copy |
| **FAIL: D3 (key consumed)** | The button doesn't fill the field, the system **Paste** from that same copy also fails, and then, from a fresh copy without touching the button, the system **Paste** fills it with the matching npub (step 8) |
| **FAIL: clearing** (report separately from D3) | The button fills the field, but the pasteboard is **not empty** afterwards |
| **INCONCLUSIVE** | **Don't Allow** was tapped or Paste from Other Apps is set to Deny; the system Paste also fails from a fresh copy (step 8); the two attempts in the first FAIL: D3 row differ; the npub doesn't match; or the clipboard may have expired |
| **BLOCKED** | No spare device without an account, or no throwaway key |

## Record (physical device only)
| Date | Device / iOS | Build | Attempt | Allow Paste shown? | Paste setting | Button filled field? | System Paste, same copy | System Paste first, fresh copy | npub matched? | Pasteboard afterwards | Result |
|---|---|---|---|---|---|---|---|---|---|---|---|
| | | | 1 | | | | | | | | not run |
| | | | 2 (if step 7 says to repeat) | | | | | | | | |

Also record that VoiceOver was off and the key is retired. Send back the table and, if useful, a screenshot of the import screen. No nsec.
