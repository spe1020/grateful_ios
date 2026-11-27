---
title: "Grateful Day Phase 1 Test Run Sheet and Results"
tags: [grateful-day, testing, evidence]
status: active
created: 2026-11-25
---

Maintained by Ship. Simulator results and physical-device results are kept in separate tables and never substitute for each other.
Current main: iOS `f040127`, web `2b15ce6` (#50). `f040127` adds the release-blocker fixes #38 (interrupted publish), #41 (conflict and deletion pickers) and #42 (rewriting a day after its remote deletion), plus the test-only #35, to `10ae4d6`. **No result recorded below ran on `f040127`**; each keeps the build it ran on. Web #50 deployment: succeeded per Chief (run 45725870933, github-pages deployment 8072677523).
Physical-device procedures: `GRATEFUL_DAY_ICLOUD_RECOVERY_RUN_SHEET.md`, `GRATEFUL_DAY_INTERRUPTED_SYNC_RUN_SHEET.md`.

## Evidence rule (handoff §4, for agent-run results)
Each result needs: iOS and web commit; event IDs and relay destinations for anything published; a result bundle or screenshot. Without artefacts it is **BLOCKED**, not PASS. No private keys or journal text.

## A. Simulator (executor: Sous; independent review: Audit)
| # | Scenario | iOS | Web | Event IDs / relays | Artefact | Result | Audit |
|---|---|---|---|---|---|---|---|
| S1 | Web → iOS private sync | | | | | not yet reported | |
| S2 | Create private on web, retrieve and decrypt on iOS | `10ae4d6` | `2b15ce6` | B's kind 36669 `ecf2617b6f872af600ff2bb45c69be2b624012bd539b6248ff6ed0888a69ae49` (`d=2026-11-27`): web sent to nos.lol and relay.nostr.net, both OK; Audit found it on both; not found on primal (EOSE); damus WebSocket error. Web also republished B's settings, kind 30078 `f32f2159`, to the same two | `RESEARCH/GRATEFUL_DAY_PHASE1_EVIDENCE/S2B_*` | **PASS** (Simulator; P143) | PASS (1d5aecab) |
| S3 | Deletion propagation, kind 5 | | | | | not yet reported | |
| S4 | Switching between two disposable identities | | | | | not yet reported | |
| S5 | No cross-account read, modify or publish | | | | | not yet reported | |
| S6 | Guest journal and account adoption | | | | | not yet reported | |
| S7 | Conflict and set-aside preservation | | | | | not yet reported | |
| S8 | Relay configuration stays with its identity | `10ae4d6` | no web commit reported | B kind 10002 `5a41a795` (setup). B's kind 36669 `4d73a0b0fdf283dd8a0954a926013182539d0f2bf18002013c583470fe21eff7` (`d=2026-11-26`): sent to nos.lol and relay.nostr.net, both OK; Audit found it on both; probed absent on primal (EOSE). damus: see note | `RESEARCH/GRATEFUL_DAY_PHASE1_EVIDENCE/S8_*` | **PASS** (Simulator; P138) | PASS: discovery interim (89450ce1), publish half (7bb5983f) |

**S2 notes** (Sous 0ff12f7e, Audit 1d5aecab; synthetic marker, not journal text; no key imported, B was already signed in):
- iOS showed the web-created marker in the Today editor. The relay content is nip44 ciphertext with no plaintext marker.
- The iOS pass ended `signed 0, sent 0, conflicts 0`: nothing was echoed back for 11-27 and no false conflict appeared. The one row due, 11-25 `6b1ac8d0`, was held by D5 on this build; the only banner was the old 11-25 "Kept both".

**S8 notes** (synthetic marker, not journal text; no key imported):
- **damus leg:** the only evidence it wasn't sent there is the app's send line, which names just nos.lol and relay.nostr.net. damus wasn't probed absent: Sous got 503 on an upgrade request and Audit's probe got a WebSocket error. The re-probe on 2026-11-27 still got 503 (`S8_DAMUS_REPROBE_2026_11_27.txt`). Chief ruled to stop retrying (P142); Audit agrees and rated it not blocking.
- **Relay list unknown:** in the stalled 00:53 pass the app logged `write: unknown` and `nothing published`. It held writes and didn't fall back to the default write relays.

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

Measurement (§7, Sous): first sync of a 60-day guest backlog (run 2, test build `cf1a5ec`, no app code change): **20 of 60 days synced at the 1800 s cap, app open throughout**; the 60th day wasn't reached. Audit PASS as a measurement (96d4b36c); artefacts `backlog-run2-*`. Whether to change the behaviour is Seth's decision M.

Executor status, 2026-11-26: throwaway identities are A `npub1h3pjhv…3nts2` and B `npub1t8293…fmxgef`. S2 and S8 are the only formal scenario results recorded here; rows marked "not yet reported" have no formal result in this sheet.

## B. Physical devices (executor: Seth only)
| ID | Test | Result | Date | Build | What was verified (Seth) | Further evidence |
|---|---|---|---|---|---|---|
| D1 | Private iOS → web interoperability | **PASS, user-verified** | 2026-11-25 | iPhone `25d7f06`; web production (commit inferred `9347018`, before #50; not confirmed by Seth) | Imported test identity C; private 2026-11-24 reflection published; 5 approved relays acknowledged; fresh private browser session on production, same identity; appeared without reload; decrypted and matched | **Not supplied:** screenshot, event ID, names of the 5 relays |
| D2 | Light mode and layout | **PASS, user-verified** | 2026-11-25 | iPhone `25d7f06` (assumed same session as D1) | Today footer above floating tab bar; secondary text readable; Today, Calendar, Settings correct; dark-mode footer also passed | **Not supplied:** screenshots, device model, iOS version |
| D3 | iCloud Keychain recovery (exit criterion 2) | **BLOCKED** | | `f040127` (planned) | awaiting devices | |
| D4 | Interrupted sync (background/foreground) | **not run** | | | | |

The handoff doesn't require repeating D1 or D2. Missing evidence doesn't change their user-verified PASS. D1 and D2 ran on `25d7f06`, which predates #29. D1 is not evidence for web → iOS. D2 is not a VoiceOver or accessibility check.
