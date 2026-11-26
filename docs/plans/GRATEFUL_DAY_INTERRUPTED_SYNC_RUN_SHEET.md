---
title: "Grateful Day Interrupted-Sync Run Sheet for Seth's iPhone"
tags: [grateful-day, ios, device-testing, sync]
status: active
created: 2026-11-25
---

**Seth runs this on a physical iPhone. No Simulator result may be recorded for it.** Not yet run. Not one of the four Phase 1 exit criteria (handoff §1); it's the device test reserved in §4.
Expected behavior was read from source at `10ae4d6`: leaving for the background stops the running sync and closes relay connections; returning starts a new one. A send that got no answer is retried after 30 s, then 2 min, 10 min, then 1 h.

## Before you start
- The iPhone stays on its current account (test identity C). **No sign-out, no account switch, no Remove, no reinstall, don't delete the app.**
- Your phone's last recorded build is `25d7f06`. That lacks the #29 owner-at-write fix. Either is your choice:
  - **Stay on `25d7f06`** (no change to the phone). Record that build. Its sync code is unchanged since then.
  - **Update to `10ae4d6`** by running over the installed app from Xcode (same team Z26TJQZZWC, same bundle ID). This changes the app on your phone. Days written before #29 with no owner are still not migrated, so keep the no-account-switch rule.
- This test writes today's reflection and publishes it (encrypted) as C. **If today already holds text you care about, run it another day.** Use made-up test lines only.
- Have: the Mac with **Console.app** and a cable; a private browser window on gratefulday.space signed in as C.
- Console.app: select the iPhone, filter `subsystem:app.gratefulday.ios`, start streaming. **Don't run from Xcode's debugger** (use the app's icon): a debugger can keep the app from being suspended. Relay names show as `<private>`; the stage lines are what matter. Don't share unfiltered device logs.

## Runs
Do each once, with a new edit each time (a new edit starts a fresh retry schedule). Wait for the Saving mark to clear before the next run. Note the clock time of each action.

| Run | Do | Then |
|---|---|---|
| I1 Leave at once | Change today's line to "interrupt one". Without pausing, go to the Home Screen | Wait 2 minutes. Reopen |
| I2 Leave during the send | Change it to "interrupt two". Stay in the app, watch Console for `publish pass` or `read before send`, and go Home the moment either appears | Wait 2 minutes. Reopen |
| I3 Lock during the send | Change it to "interrupt three". Same trigger as I2, but press the side button to lock | Wait 2 minutes. Unlock, reopen |
| I4 Rapid in and out | Change it to "interrupt four". Go Home and back five times, about a second apart | Stay in the app |

After each reopen, keep the app open and don't type for up to **5 minutes**.

**Was it really interrupted?** For I1 to I3 look for `publish pass stopped`, `pass stopped`, or a `not sent` line, or a `sending` line with no `saved to the account` before you left. If sync had already finished (`saved to the account` before you left), that attempt didn't test interruption: repeat it once with a new edit. With no log evidence, record **INCONCLUSIVE**, even if everything looks right.

## PASS / FAIL (each run)
| Check | PASS | FAIL |
|---|---|---|
| Text on iPhone | Exactly the line you typed, after reopen | Lost, partly lost, or reverted |
| Finishes | Saving mark clears within 5 minutes of reopening, online, without typing | Still showing after 5 minutes |
| Web | Fresh load shows today once, with the new line | Missing, older, or unreadable |
| No false conflict | No "was also changed elsewhere", "was replaced by a version saved elsewhere", conflict screen, or new Set aside item | Any of these (you edited nowhere else during the run) |
| Stability | No crash, freeze or blank screen | Any of these |

Don't edit on the web or another device during a run. If a conflict screen appears, screenshot it (cover text), choose **Not now**, and stop.
If a run fails: stop, leave the app as it is, note the time, and save the filtered Console lines. If a mark is stuck, record how long; it may be waiting on the 10-minute or 1-hour retry, which is still a finding.

## Result record (physical iPhone only)
| Run | Date/time | Build / iOS | Interrupted? (log line) | Minutes to clear | Text | Web | False conflict | Result | Evidence |
|---|---|---|---|---|---|---|---|---|---|
| I1 | | | | | | | | not run | |
| I2 | | | | | | | | not run | |
| I3 | | | | | | | | not run | |
| I4 | | | | | | | | not run | |

Send back screenshots (text covered), the filtered stage lines and the times. No nsec or reflection text. Event IDs can be looked up from C's public npub and are recorded as pending until then.
