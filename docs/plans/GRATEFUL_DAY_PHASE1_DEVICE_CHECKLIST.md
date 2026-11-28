---
title: "Grateful Day Phase 1 Physical-Device Checklist"
tags: [grateful-day, ios, device-testing]
status: active
created: 2026-11-22
---

Status is only what Seth reported. Run order, steps and PASS/FAIL criteria: `GRATEFUL_DAY_PHASE1_RECOVERY_RUN_SHEET_2026_11_25.md`. Updated 2026-11-25 by Ship (Seth event bc767b8f; Chief handoff 34b024d2; decision log P86).

Code: iOS main `c9101349` (#29; Xcode builds only, no TestFlight or release). Web production `9347018` (#45–#49), deployment 8057856117. **Phase 1 is not closed.**

## Verified: USER-VERIFIED PASS, 2026-11-25 (Seth-reported)
| # | Scenario | Scope and version | Evidence |
|---|----------|-------------------|----------|
| 1 | iOS → web private decryption, same identity | Identity C (`npub1jlag3…`), iOS → web, private only; reflection dated 2026-11-24. Automatic sync, Saving mark cleared, 5 approved relays acknowledged, fresh private window, appeared without manual refresh, decrypted and matched. Web `9347018` (inferred from deploy time; Seth to confirm test time). iOS build: **pending from Seth** | Seth's report (bc767b8f). Screenshots/logs pending |
| 10 | Today footer clear of tab bar; light-mode layout and readability | Physical iPhone, light mode: footer fully above floating tab bar, gray text readable, Today/Calendar/Settings with no significant overlap or clipping. Earlier dark-mode footer check also passed. iOS build: **pending from Seth**. No separate small-screen check reported | Seth's report (bc767b8f). Screenshots pending |

Item 1 is not evidence for web → iOS, encryption in other scenarios, account switching or recovery. Item 10 is not an accessibility or VoiceOver check.

## Verified: earlier sessions (Seth-reported)
- Physical-iPhone installation and launch; local journal saving
- Nostr identity creation + iCloud Keychain backup (first session; backup not re-checked since)
- Identity import and connected-account publishing (C)
- Publishing disclosure accepted
- Foreground automatic sync after saving; Saving mark clears
- Encrypted kind 36669 publish; multiple relay acknowledgments; event retrievable
- Multiple existing account-owned rows stayed isolated (this observation only; not a switching test)
- No journal data or private keys lost (first session)

## Open (device owner: Seth)
| # | Scenario | Status / needs |
|---|----------|----------------|
| 5 | Keychain recovery on a second device | **BLOCKED**: Seth to confirm a second device and the throwaway-backup preconditions (run sheet step 3) |
| 2 | Web → iOS sync | Not run (step 4). Needs a throwaway whose nsec Seth holds |
| 4 | Deletion + archived versions | Not run (step 4 PASS (b) for archived versions; step 5 for deletion) |
| 6 | Account switching/separation and guest adoption with #29 | Not run (step 6). Simulator or spare device only |
| 6b | Account removal | Not scheduled. Destructive; throwaway device only, with Seth's approval |
| 8 | VoiceOver | Not run (step 7) |
| 8b | Other accessibility checks (e.g. large text, small screen) | Not reported |
| 3 | Cross-device conflict resolution | Two devices, same identity. No steps written yet |
| 7 | Data Protection | Device lock-state check. No steps written yet |
| 9 | Background/foreground behavior | Networking fixes #20–#22 merged. No steps written yet; not run |
| P53 | Responsiveness after connecting an account | UI responsive, typing smooth for 2 min after key creation. Context: XCUITest waited 54–100 s for app idle after a key existed |

Web relay isolation (#44, fixed by #47) and the web author check (#46) are merged and live with Audit PASS. No separate device result from Seth is recorded here.

## Known limitations (accepted by Seth, per Chief e44902a9)
- No migration for ownerless days written before #29: **keep the no-account-switch rule on the primary iPhone**
- Web does not find a relay list that exists only on non-default relays
- DM gift wraps fail closed

## Defects
Previous list cleared 2026-11-25. Fix attributions follow Chief's handoff; they are code merges, not separate device retests.

Closed by merged PRs:
- First-connect sync not starting immediately; unconnectable relays blocking publishing: #20
- Save while open not triggering sync: #21
- Repeated timeouts on unresponsive relays: #20, #22 (a relay that never connects is remembered for 10 minutes)

Open:
| Item | Owner / next step |
|---|---|
| No nsec export (key-export r3) | Prep + Audit finalize spec; Seth decides, including whether it's required to close Phase 1. No implementation until approved |
| D-R1: `relay.nostr.band` still a default relay (persistent failures) | Seth decision. #22 reduces repeat dialing; it doesn't change the relay list. The earlier `relay.damus.io` failure report shares #22's mitigation; damus is also still a default |

## Rules
No merges, releases, TestFlight, deploys, or event-format/encryption changes without Seth's approval. An item moves to Verified only with a dated result and evidence; pending evidence is marked as pending. Never "Remove account and local data" or "Delete backup" on the primary iPhone.
