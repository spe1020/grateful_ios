---
title: "Grateful Day Phase 1 Test Run Sheet and Results"
tags: [grateful-day, testing, evidence]
status: active
created: 2026-11-25
---

Maintained by Ship. Simulator results and physical-device results are kept in separate tables and never substitute for each other.
Current main: iOS `10ae4d6` (#30, tests only; app code same as `c910134`), web `2b15ce6` (#50). Web #50 deployment: succeeded per Chief (run 45725870933, github-pages deployment 8072677523).
Physical-device procedures: `GRATEFUL_DAY_ICLOUD_RECOVERY_RUN_SHEET.md`, `GRATEFUL_DAY_INTERRUPTED_SYNC_RUN_SHEET.md`.

## Evidence rule (handoff §4, for agent-run results)
Each result needs: iOS and web commit; event IDs and relay destinations for anything published; a result bundle or screenshot. Without artefacts it is **BLOCKED**, not PASS. No private keys or journal text.

## A. Simulator (executor: Sous; independent review: Audit)
| # | Scenario | iOS | Web | Event IDs / relays | Artefact | Result | Audit |
|---|---|---|---|---|---|---|---|
| S1 | Web → iOS private sync | | | | | not yet reported | |
| S2 | Create private on web, retrieve and decrypt on iOS | | | | | not yet reported | |
| S3 | Deletion propagation, kind 5 | | | | | not yet reported | |
| S4 | Switching between two disposable identities | | | | | not yet reported | |
| S5 | No cross-account read, modify or publish | | | | | not yet reported | |
| S6 | Guest journal and account adoption | | | | | not yet reported | |
| S7 | Conflict and set-aside preservation | | | | | not yet reported | |
| S8 | Relay configuration stays with its identity | | | | | not yet reported | |

### Sign-out warning and local data (added 2026-11-25; Audit §8, Chief)
None of S1 to S8 covers the sign-out fix (`signOutCounts`, #29). Run this with S4, on the disposable Simulator only, using throwaway A. It's coverage for an existing fix, not a ninth exit-criterion scenario. **Sign out only. Never Remove account and local data, never Delete backup.**

| Step | Do | PASS |
|---|---|---|
| SO1 | As A with everything saved (no Saving mark): Settings > Account > Sign out. Screenshot, **Cancel** | Heading "Sign out on this iPhone?" with "Your journal key will be removed from this iPhone. Your reflections stay here, and you can keep writing." **No** unsaved-reflection paragraph and no before-you-signed-in paragraph. Cancel leaves A connected |
| SO2 | Block the app's network access (record how), change today's line, open Sign out | "1 reflection hasn't been saved to your account yet. It'll stay on this iPhone and will be saved when you sign back in to this account. It won't be saved to any other account." Synced days aren't counted |
| SO3 | Confirm (**Sign out**, or **Sign out anyway** when A has no backup; the latter also shows the no-backup paragraph). Open Calendar | A's days, including the unsaved one, are still on the device and read-only (opened as from another account); text unchanged |
| SO4 | Restore network, reconnect A, accept the publishing sheet if shown, wait for the Saving mark to clear | All of A's days are there; the unsaved change publishes under A only; no new conflict or Set aside item |

With two or more unsaved days the line must read "N reflections haven't been saved to your account yet. They'll stay on this iPhone and will be saved when you sign back in to this account. They won't be saved to any other account." The before-you-signed-in paragraph counts only reflections with no account; check it in S6 if a guest day exists while an account is connected, otherwise record "not observed".
FAIL: wrong or missing count or wording, any local reflection lost or changed, or A's text published under another key. If the network can't be blocked without disturbing other runs, record SO2 to SO4 **BLOCKED**.

| Check | iOS | Event IDs / relays | Artefact | Result | Audit |
|---|---|---|---|---|---|
| SO1–SO4 | | | | not yet reported | |

Measurement (§7, Sous): first sync of a 60-day guest backlog: **not yet reported**.

Executor status, 2026-11-25: Sous reports two throwaway identities created (A `npub1h3pjhv…3nts2`, B `npub1t8293…fmxgef`) and the harness in progress. No scenario result yet.

## B. Physical devices (executor: Seth only)
| ID | Test | Result | Date | Build | What was verified (Seth) | Further evidence |
|---|---|---|---|---|---|---|
| D1 | Private iOS → web interoperability | **PASS, user-verified** | 2026-11-25 | iPhone `25d7f06`; web production (commit inferred `9347018`, before #50; not confirmed by Seth) | Imported test identity C; private 2026-11-24 reflection published; 5 approved relays acknowledged; fresh private browser session on production, same identity; appeared without reload; decrypted and matched | **Not supplied:** screenshot, event ID, names of the 5 relays |
| D2 | Light mode and layout | **PASS, user-verified** | 2026-11-25 | iPhone `25d7f06` (assumed same session as D1) | Today footer above floating tab bar; secondary text readable; Today, Calendar, Settings correct; dark-mode footer also passed | **Not supplied:** screenshots, device model, iOS version |
| D3 | iCloud Keychain recovery (exit criterion 2) | **BLOCKED** | | `10ae4d6` | awaiting devices | |
| D4 | Interrupted sync (background/foreground) | **not run** | | | | |

The handoff doesn't require repeating D1 or D2. Missing evidence doesn't change their user-verified PASS. D1 and D2 ran on `25d7f06`, which predates #29. D1 is not evidence for web → iOS. D2 is not a VoiceOver or accessibility check.
