---
title: "Grateful Day Conflict Picker One-Finger Device Check"
tags: [grateful-day, ios, device-testing, conflict]
status: active
created: 2026-11-25
---

**Seth runs this with one finger on a physical device. Not yet run. No Simulator result counts.** Companion to the other Phase 1 run sheets. Requested by Chief (decision log P104).

**Why:** suspected defect **D2** (Sous, Simulator, iOS `10ae4d6`, reproduced twice): an automated tap on the centre of **Keep this iPhone's** selected **Keep your account's**, and Done then kept the account's text. It isn't yet known whether a finger does the same. A pass here doesn't replace Sous's two automated checks.

Build: `10ae4d6` unless Chief names a fix commit. Record the commit. Screen text and expected results were read from source at `10ae4d6`.

## Safety
- **Throwaway identity only. Never your real account.**
- **Not on your primary iPhone.** It would need an account switch.
- Use a physical iPhone or iPad with no Grateful Day account and no written entries. If it has either, stop.
- No **Remove account and local data**, no **Delete backup**, no app deletion or cleanup afterwards.
- Made-up test lines only. Cover entry text in screenshots. Never screenshot or send the nsec.

## You need
- That device (iOS 17+), a Mac with Xcode to install the build (signing team `Z26TJQZZWC`; don't select the primary iPhone as the Run destination).
- A **new** throwaway identity made outside the app, with its nsec in a password manager: the web needs it, and the app can't export a key yet. Note its npub.
- A computer with a private browser window on gratefulday.space, signed in as that identity. It must stay online while the device is offline.
- Finish all rounds on the same local date (both apps only let you edit today).

## Setup
1. Device: **Settings > Account > Use my Nostr account**, paste, **Continue**, check the npub, **Use this account**. At the backup offer: **Don't back up > Continue without backup**. At "What's private in your journal": **Continue**.
2. Write "base" on **Today**. Stop typing, keep the app open until the **Saving to your account** mark clears. Reload the web and confirm it shows "base".

## Make a conflict (before each round; N = 1, 2, 3)
1. The Saving mark is gone, and device and web show the same text.
2. Device: Airplane Mode on, with Wi-Fi off.
3. Device: replace today's text with "phone N".
4. Web: reload, replace today's note (don't add a second one) with "web N", keep it **Private**, save.
5. Device: Airplane Mode off, go to the Home Screen, reopen the app. Don't type.
6. Tap the line "Your reflection from <date> was also changed elsewhere. Choose what to keep." or "This reflection was also changed elsewhere. Both versions are kept on this iPhone."
7. Check that **Your account** shows "web N" and **This iPhone** shows "phone N". If they're swapped or wrong, that's a FAIL: screenshot, tap **Not now**, stop.

No conflict after two reopens and 5 minutes online: record BLOCKED. A conflict before step 3 is a separate finding (see D1, decision log P102): record it, tap **Not now**, stop.

## Hit-area probe (round 1, before tapping Done)
The options are **Keep both** (preselected), **Keep this iPhone's** and **Keep your account's**. The line under them changes with the selection:

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

If any tap selects another option, screenshot or screen-record it (text covered). That confirms D2. Still do the rounds: before **Done**, note both the option you tapped and the one shown as selected.

## Rounds: apply each option once
In each round, first make sure a **different** option is selected, then tap the target **once, in the centre**. Note the checkmark and line, then tap **Done**. Keep the app open until the Saving mark clears (if one shows), then reload the web.

To open Set aside: on **Today**, tap "An earlier version of this reflection is in Set aside." Items from earlier rounds stay there; the newest is first.

| Round | Tap | Today on device | Set aside | Web after reload |
|---|---|---|---|---|
| 1 | Keep this iPhone's | "phone 1" | New: "web 1", with "You kept the other version of this day." | "phone 1" |
| 2 | Keep your account's | "web 2" | New: "phone 2", same reason | "web 2" |
| 3 | Keep both | "web 3" then "phone 3", as separate notes | **No new item** | Both, "web 3" first |

Between rounds, repeat **Make a conflict**.

## PASS / FAIL
- **PASS:** all nine probe taps and all three rounds select the option tapped, and each round's three results match the table.
- **FAIL, selection (D2 confirmed):** any tap inside an option's row selects a different option.
- **FAIL, result:** the right option shows as selected, but the kept text, Set aside or web differs from that option's row. Also fail if either text is neither on the day nor in Set aside. Stop and leave the device as it is.
- **INCONCLUSIVE:** a tap may have landed outside the row or between two rows and you can't repeat it, or the web couldn't be checked.
- **BLOCKED:** a prerequisite is missing or no conflict appears.

Not covered: the two-option screens (deleted from the account; deleted on this iPhone), several conflicting days, **Keep both for all**, VoiceOver.

## Result record (physical device only)
| Date | Device / iOS | Build | Probe | Round 1 | Round 2 | Round 3 | Overall | Evidence |
|---|---|---|---|---|---|---|---|---|
| | | | | | | | not run | |

Send back both tables, screenshots (text covered), the device model, iOS version, build and throwaway npub. No nsec, no reflection text.
