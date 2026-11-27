---
title: "Grateful Day Interrupted-Sync Run Sheet for Seth's iPhone"
tags: [grateful-day, ios, device-testing, sync]
status: active
created: 2026-11-25
---

> **Don't run this now. It's in no run plan.** It's written for the iPhone that holds test identity C, which per Chief (2026-11-27) is Seth's primary iPhone, and the primary iPhone isn't used for testing. A version for a spare device would need new setup steps.

**Seth runs this on a physical iPhone. No Simulator result may be recorded for it.** Not yet run. Not one of the four Phase 1 exit criteria (handoff §1); it's the device test reserved in §4.
Expected behavior was read from source at `a254289`: leaving for the background stops the running sync and closes all its relay connections; returning starts a new one. A sync pass now uses one connection per relay for its reads and sends (#45). If a connection that had opened drops, that relay is dialed again at most once in the pass; if it never opened, or drops a second time, the pass doesn't dial it again. A send that got no answer is retried after 30 s, then 2 min, 10 min, then 1 h. If you leave after enough relays accepted a send but before the check that follows it finished, a later sync repeats that check and then marks the day saved (the #38 fix).

## Before you start
- The iPhone stays on its current account (test identity C). **No sign-out, no account switch, no Remove, no reinstall, don't delete the app.**
- **Build: `a254289` only.** Your phone's last recorded build is `25d7f06`, which has none of the later fixes. Installing changes the app on your phone, so it's your choice; **if you don't update, don't run this sheet.**
  - `git -C <your grateful_ios checkout> fetch origin`, then `git -C <your grateful_ios checkout> worktree add ../grateful_ios-interrupt a254289` (a separate folder, so your working checkout isn't touched). In it, `git rev-parse --short HEAD` must print `a254289`.
  - Run it **over** the installed app from Xcode (same team Z26TJQZZWC, same bundle ID; don't commit the team). **Never delete the app first.** If Xcode can't install over it, stop and report; don't remove anything.
  - Days written before the #29 fix with no owner are still not migrated, so keep the no-account-switch rule.
  - After installing, stop running from Xcode, open the app from its icon online, don't type, and wait up to 5 minutes for any Saving mark to clear. A conflict line or screen, or a mark still showing, **before I1** isn't an interruption result: screenshot (text covered), choose **Not now** if a screen is open, stop and report it.
- This test writes today's reflection and publishes it (encrypted) as C. **If today already holds text you care about, run it another day.** Use made-up test lines only.
- Have: the Mac with **Console.app** and a cable; a private browser window on gratefulday.space signed in as C.
- Console.app: select the iPhone, filter `subsystem:app.gratefulday.ios`, start streaming. **Don't run from Xcode's debugger** (use the app's icon): a debugger can keep the app from being suspended. The text after a line's stage name (relay names, counts, reasons, event ID prefixes) shows as `<private>`; the stage names are what matter, so match lines by their order. Don't share unfiltered device logs.

## Runs
Do each once, with a new edit each time (a new edit starts a fresh retry schedule). Wait for the Saving mark to clear before the next run. Note the clock time of each action.

| Run | Do | Then |
|---|---|---|
| I1 Leave at once | Change today's line to "interrupt one". Without pausing, go to the Home Screen | Wait 2 minutes. Reopen |
| I2 Leave during the send | Change it to "interrupt two". Stay in the app, watch Console for `publish pass` or `read before send`, and go Home the moment either appears | Wait 2 minutes. Reopen |
| I3 Lock during the send | Change it to "interrupt three". Same trigger as I2, but press the side button to lock | Wait 2 minutes. Unlock, reopen |
| I4 Rapid in and out | Change it to "interrupt four". Go Home and back five times, about a second apart | Stay in the app |

After each reopen, keep the app open and don't type for up to **5 minutes**.

**Was it really interrupted?** For I1 to I3 look for `publish pass stopped`, `pass stopped`, a `not sent` line, a `not saved to the account yet` line, or a `sending` line with no `saved to the account` before you left. After reopening, `re-checking after an interrupted send` shows the #38 path ran; record whether it appeared. It also counts as evidence of interruption. It needn't appear: it depends on where the send was when you left. If sync had already finished (`saved to the account` before you left), that attempt didn't test interruption: repeat it once with a new edit. With no log evidence, record **INCONCLUSIVE**, even if everything looks right.

`sockets this pass` is logged after any pass that dialed a relay, whether or not it was stopped. **It isn't evidence of interruption.** With #45 a pass may finish sooner than before (not measured for a single reflection). If the repeat also finishes before you leave, record **INCONCLUSIVE**.

## PASS / FAIL (each run)
| Check | PASS | FAIL |
|---|---|---|
| Text on iPhone | Exactly the line you typed, after reopen | Lost, partly lost, or reverted |
| Finishes | Saving mark clears within 5 minutes of reopening, online, without typing | Still showing after 5 minutes |
| Web | Fresh load shows today once, with the new line | Missing, older, or unreadable |
| No false conflict | No "was also changed elsewhere", "was replaced by a version saved elsewhere", conflict screen, or new Set aside item | Any of these. You edited nowhere else, so on this build it's a real finding |
| Stability | No crash, freeze or blank screen | Any of these |

Don't edit on the web or another device during a run, including while the app is closed or in the background. After an interrupted send, an edit made elsewhere can still show as a conflict (both texts are kept), which would spoil the run. If a conflict screen appears, screenshot it (cover text), choose **Not now**, and stop.
If a run fails: stop, leave the app as it is, note the time, and save the filtered Console lines. If a mark is stuck, record how long; it may be waiting on the 10-minute or 1-hour retry, which is still a finding.

## Result record (physical iPhone only)
| Run | Date/time | Build / iOS | Interrupted? (log line) | Minutes to clear | Text | Web | False conflict | Result | Evidence |
|---|---|---|---|---|---|---|---|---|---|
| I1 | | | | | | | | not run | |
| I2 | | | | | | | | not run | |
| I3 | | | | | | | | not run | |
| I4 | | | | | | | | not run | |

Send back screenshots (text covered), the filtered stage lines and the times. No nsec or reflection text. Event IDs can be looked up from C's public npub and are recorded as pending until then.
