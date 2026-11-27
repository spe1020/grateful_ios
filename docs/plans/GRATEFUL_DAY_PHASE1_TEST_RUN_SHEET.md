---
title: "Grateful Day Phase 1 Test Run Sheet and Results"
tags: [grateful-day, testing, evidence]
status: active
created: 2026-11-25
---

Maintained by Ship. Simulator results and physical-device results are kept in separate tables and never substitute for each other.
Baseline: iOS `edaafda`, web `2b15ce6` (#50). `edaafda` adds only the test-only #44 to `f040127`; #34 (merged 2026-11-27 17:41Z, as `1d364f8`) added these three documents only. `f040127` adds the release-blocker fixes #38 (interrupted publish), #41 (conflict and deletion pickers) and #42 (rewriting a day after its remote deletion), plus the test-only #35, to `10ae4d6`. **Of the results recorded below, only S3 iOS → web, S4–S6 and SO1–SO4 ran on `f040127`**; each keeps the build it ran on. Web #50 deployment: succeeded per Chief (run 45725870933, github-pages deployment 8072677523).
iOS `main` has since moved to `a254289` (#46), with app changes that include key export (#40), connection reuse (#45) and the other-account count (#46). No scenario or device result here ran on it.
Physical-device procedures: `GRATEFUL_DAY_ICLOUD_RECOVERY_RUN_SHEET.md`, `GRATEFUL_DAY_INTERRUPTED_SYNC_RUN_SHEET.md`.

## Evidence rule (handoff §4, for agent-run results)
Each result needs: iOS and web commit; event IDs and relay destinations for anything published; a result bundle or screenshot. Without artefacts it is **BLOCKED**, not PASS. No private keys or journal text.

## A. Simulator (executor: Sous; independent review: Audit)
| # | Scenario | iOS | Web | Event IDs / relays | Artefact | Result | Audit |
|---|---|---|---|---|---|---|---|
| S1 | Web → iOS private sync | | | | | not yet reported | |
| S2 | Create private on web, retrieve and decrypt on iOS | `10ae4d6` | `2b15ce6` | B's kind 36669 `ecf2617b6f872af600ff2bb45c69be2b624012bd539b6248ff6ed0888a69ae49` (`d=2026-11-27`): web sent to nos.lol and relay.nostr.net, both OK; Audit found it on both; not found on primal (EOSE); damus WebSocket error. Web also republished B's settings, kind 30078 `f32f2159`, to the same two | `RESEARCH/GRATEFUL_DAY_PHASE1_EVIDENCE/S2B_*` | **PASS** (Simulator; P143) | PASS (1d5aecab) |
| S3 | Deletion propagation, kind 5 (this row records iOS → web only) | `f040127` | `2b15ce6` | B's kind 36669 `93cb3567ef472e53ae48d98bde6e001f7b7b8feaf50a8c3e0113d0490c319b62` (`d=2026-11-27`), then kind 5 `cc3ef0724dd5af404809a80f95adb272cf3e03f3c5ae759881330ec4932f4a8f`: each sent to nos.lol and relay.nostr.net, both OK. After the deletion, no 36669 for that day on those two, primal or nostr.wine. Web read: no note for that day | `RESEARCH/GRATEFUL_DAY_PHASE1_EVIDENCE/S3C_IOS_TO_WEB_*` | **PASS** (Simulator, iOS → web; P157) | PASS (025a2d8d) |
| S4 | Switching between two disposable identities | `f040127` | not used | A → B → A; each import showed that account's npub. B didn't see A's text as its own. Probe while B was signed in: no A marker under B | `RESEARCH/GRATEFUL_DAY_PHASE1_EVIDENCE/S456_2026_11_27/` | **PASS** (Simulator) | PASS (6d0d9700) |
| S5 | No cross-account read, modify or publish | `f040127` | not used | A's kind 36669 `483ab4a6f307ac9e1f7af4c4eec4305f0ae64bf31c249a0af84e87f31219300f`: nos.lol and primal OK; damus failed(send). Probes found A's markers under A only; B has no 36669 for 11-27 | `RESEARCH/GRATEFUL_DAY_PHASE1_EVIDENCE/S456_2026_11_27/` | **PASS** (Simulator) | PASS (6d0d9700) |
| S6 | Guest journal and account adoption | `f040127` | not used | Guest text adopted by A; kind 36669 `a0f5ce12…` (`d=2026-11-27`): nos.lol and primal OK; damus failed(send). Later replaced by A's S5 write | `RESEARCH/GRATEFUL_DAY_PHASE1_EVIDENCE/S456_2026_11_27/` | **PASS** (Simulator) | PASS (6d0d9700) |
| S7 | Conflict and set-aside preservation | | | | | not yet reported | |
| S8 | Relay configuration stays with its identity | `10ae4d6` | no web commit reported | B kind 10002 `5a41a795` (setup). B's kind 36669 `4d73a0b0fdf283dd8a0954a926013182539d0f2bf18002013c583470fe21eff7` (`d=2026-11-26`): sent to nos.lol and relay.nostr.net, both OK; Audit found it on both; probed absent on primal (EOSE). damus: see note | `RESEARCH/GRATEFUL_DAY_PHASE1_EVIDENCE/S8_*` | **PASS** (Simulator; P138) | PASS: discovery interim (89450ce1), publish half (7bb5983f) |

**S2 notes** (Sous 0ff12f7e, Audit 1d5aecab; synthetic marker, not journal text; no key imported, B was already signed in):
- iOS showed the web-created marker in the Today editor. The relay content is nip44 ciphertext with no plaintext marker.
- The iOS pass ended `signed 0, sent 0, conflicts 0`: nothing was echoed back for 11-27 and no false conflict appeared. The one row due, 11-25 `6b1ac8d0`, was held by D5 on this build; the only banner was the old 11-25 "Kept both".

**S3 iOS → web notes** (Audit 025a2d8d; run 2, 17:02:06–17:08:00Z on 2026-11-27, under `caffeinate -dims`, account B):
- Audit's limit: "The relays removed the 36669 themselves when they accepted the kind 5, so this doesn't show the web applying a kind 5 while a relay still holds the event."
- Audit's limit: "Simulator only."
- Run 1 isn't counted: the Mac was sleeping (Chief, eae7b212). Run 2 used a new marker.
- This row doesn't record the web → iOS direction.

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
| SO1 | `f040127` | none for this check | `RESEARCH/GRATEFUL_DAY_PHASE1_EVIDENCE/S456_2026_11_27/` | **PASS** | PASS (6d0d9700) |
| SO2 | `f040127` | none for this check | `RESEARCH/GRATEFUL_DAY_PHASE1_EVIDENCE/S456_2026_11_27/` | **PASS, with a stated limit:** the network block was "the app's `-uiTestNoRelays` launch argument, not a real OS-level offline" | PASS with that limit (6d0d9700) |
| SO3 | `f040127` | none for this check | `RESEARCH/GRATEFUL_DAY_PHASE1_EVIDENCE/S456_2026_11_27/` | **PASS** | PASS (6d0d9700) |
| SO4 | `f040127` | A's kind 36669 `c3416bc8faa2909a4d626a3a6f8f99452f9ed5bcb3c48703abef0586cf6ca7fe`: nos.lol and primal OK; damus failed(send) | `RESEARCH/GRATEFUL_DAY_PHASE1_EVIDENCE/S456_2026_11_27/` | **PASS** | PASS (6d0d9700) |

**S4–S6 and SO1–SO4 notes** (run 2bad42, GD P1VAL, throwaway A and B, 2026-11-27 17:51:52–18:01Z and 18:10:48–18:18:11Z; executor Sous 0e1ff7ab; Audit 6d0d9700, record `RESEARCH/GRATEFUL_DAY_S456_IMPORT_RUN_AUDIT_2026_11_27.md`):
- Simulator only. App code `f040127`; the web wasn't used (iOS plus relay probes).
- SO1: A had no backup, so the sheet also showed the no-backup paragraph and the button read "Sign out anyway", as the sheet allows.
- The before-you-signed-in paragraph has no reported observation.
- Step 13's FAIL was the test harness, not the app (Audit agrees). A step 14 attempt was killed by an executor session restart before any paste.
- Signed out, Calendar read "3 earlier reflections from another account" for 4 expected rows. Sous (7ced0ed2): the line counts distinct dates (`JournalRepository.otherAccountDayCount()`), so no row is missing; two accounts writing on one date count once. Prep ruled (117e6792, logged as P172, Chief 04dd3046): count rows and keep the wording. This replaces P171. The change merged as #46 (`a254289`); the quote above is what the tested build showed. S4–S6 and SO1–SO4 haven't been rerun with that change.

Measurement (§7, Sous): first sync of a 60-day guest backlog (run 2, test build `cf1a5ec`, no app code change): **20 of 60 days synced at the 1800 s cap, app open throughout**; the 60th day wasn't reached. Audit PASS as a measurement (96d4b36c); artefacts `backlog-run2-*`. Seth then ruled M, connection reuse in Phase 1 (8a3b1c2b).

Rerun after M (Sous fd9d352f; test build `b674194`, which is the #45 change on `1d364f8` plus the measurement harness; one run, Simulator): **60 of 60 days synced in 76.5 s**, 2 passes, and all 60 recorded event IDs fetched from both nos.lol and primal. damus refused the connection (HTTP 503). Audit checked the evidence, including its own relay fetch (79d5b042, `RESEARCH/GRATEFUL_DAY_M_PR45_AUDIT_2026_11_27.md`); artefacts `backlog-reuse-run1*`. M merged as #45 (`e8db7bd`). The run wasn't repeated on the merged commit.

Executor status, 2026-11-27: throwaway identities are A `npub1h3pjhv…3nts2` and B `npub1t8293…fmxgef`. S2, S3 (iOS → web only), S4, S5, S6 and S8, plus SO1–SO4, are the formal results recorded here; rows marked "not yet reported" have no formal result in this sheet.

## B. Physical devices (executor: Seth only)
| ID | Test | Result | Date | Build | What was verified (Seth) | Further evidence |
|---|---|---|---|---|---|---|
| D1 | Private iOS → web interoperability | **PASS, user-verified** | 2026-11-25 | iPhone `25d7f06`; web production (commit inferred `9347018`, before #50; not confirmed by Seth) | Imported test identity C; private 2026-11-24 reflection published; 5 approved relays acknowledged; fresh private browser session on production, same identity; appeared without reload; decrypted and matched | **Not supplied:** screenshot, event ID, names of the 5 relays |
| D2 | Light mode and layout | **PASS, user-verified** | 2026-11-25 | iPhone `25d7f06` (assumed same session as D1) | Today footer above floating tab bar; secondary text readable; Today, Calendar, Settings correct; dark-mode footer also passed | **Not supplied:** screenshots, device model, iOS version |
| D3 | iCloud Keychain recovery (exit criterion 2) | **PASS, user-verified** | 2026-11-27 (reported) | not stated (sheet names `f040127`) | Seth's report (3459b698): "tested on second device and keychain restore passes" | **Not supplied:** which devices and whether either was the primary iPhone, setup (A or B), build, whether the npubs matched, whether the test reflection opened and matched, backup rows offered, screenshots (R1–R4 not itemized) |
| D4 | Interrupted sync (background/foreground) | **not run** | | | | |

The handoff doesn't require repeating D1 or D2. Missing evidence doesn't change their user-verified PASS. D1 and D2 ran on `25d7f06`, which predates #29. D1 is not evidence for web → iOS. D2 is not a VoiceOver or accessibility check.
