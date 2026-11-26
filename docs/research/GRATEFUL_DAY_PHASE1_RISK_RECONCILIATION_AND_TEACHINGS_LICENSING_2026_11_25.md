---
title: "Grateful Day Phase 1: section 8 risk reconciliation, section 9 teachings licensing, S3+ verdict (iOS 10ae4d6, web 2b15ce6)"
tags: [grateful-day, audit, phase1, risk, licensing, export]
status: active
created: 2026-11-25
---

Requested by Seth, #general event 5f1caa72 (§6, §8, §9).

## Targets
- iOS main `10ae4d6`. Since my post-merge isolation PASS at `c9101349`, the only change is #30 (`d871afa`), which is tests only.
- Web main `2b15ce6`. Since `9347018`, the only change is #50.

Read in the detached worktree REPOS/grateful_ios-audit. I ran no new test suites this turn. The evidence is code reading plus the earlier recorded runs (RESEARCH/GRATEFUL_DAY_ACCOUNT_ISOLATION_POSTMERGE_AUDIT_2026_11_25.md and the #30/#50 audits).

## S3+ verdict (export)
Drop clear-on-hide, as Prep recommends. The 60 s `expirationDate` is the only clearing. Hiding, timeout, Done, back, sign-out and backgrounding never touch the pasteboard. The S7+ test "changeCount guard works" is replaced by "hide, .inactive and timeout leave the pasteboard unchanged". Posted as event d562846e.

## §8 classification
| Risk | Class | Evidence |
|---|---|---|
| Account ownership on write/switch | Fixed defect awaiting device validation | iOS #27 owner-at-write fixed in #29. L1/L2 pinned by #30. Web L3 fixed by #50. Needs simulator scenarios 4–5. |
| Per-account relay-list isolation | Fixed defect awaiting device validation | Web #44 fixed via #45–#49 (per-account slots, legacy list dropped). iOS sync.reset on switch. Scenario 8. L4 residual Low. |
| Holding writes while discovery unresolved | Remaining test gap | Both clients by code and unit tests. No end-to-end run yet (scenario 8). |
| Wrong-author rejection | Remaining test gap | iOS DailyEntry.isValid(owner) + fetcher sig check. Web #46 + NRelay1 verifyEvent. Unit-tested. Scenario 5 end-to-end. |
| Conflict resolution and deletion safeguards | Remaining test gap | Remote delete archives before tombstoning (RemoteImporter.swift:94-96, ruling recorded). Scenarios 3 and 7. |
| Sign-out warnings and local-data preservation | Fixed defect awaiting device validation | The old `unsyncedCount` = total count bug is fixed: AccountModel.swift:213 → JournalRepository.signOutCounts (:176) counts unsaved-for-owner + guest. None of the 8 scenarios covers it. |
| Intermittent migration/a11y test failures | Remaining test gap | The a11y flake was fixed in #24 (main actor). The MigrationFailureTests byte-compare flake is still seen locally, and the failure is in the test, not the product. |
| Relay availability and retry | Remaining test gap | #20/#22 PASS with stall probes. Background interruption is reserved for Seth's device. |
| VoiceOver/accessibility | Product decision | Seth's earlier rule makes VoiceOver a release/TestFlight gate, but it isn't among the four Phase 1 exit criteria. Recommend: gate public release, not the internal TestFlight tester build. |

No item is a verified open defect or a current release blocker.

Info: `RemoteSettings.read` (RemoteJournal.swift:60) still ignores read outcomes. That's harmless now, because nothing consumes the settings. It **must** be fixed before Phase 2 item 1, where a public/private default comes from the synced setting: an incomplete read currently looks like "no settings".

## §9 teachings.json
teachings.json hasn't changed between `8acb65f` (my per-item sourcing, RESEARCH/GRATEFUL_DAY_IOS_REFLECTION_CARD_DATA_AND_SOURCES_2026_11_23.md, appendices with an evidence URL per id) and `2b15ce6`. It has 252 items, all with a quote.

Usable as is, with a translator credit:
- Stoic: Long 80, 232, 233, 235, 236, 244, 245, 248, 250. Carter 72. Higginson 25 (blend). Gummere 83, 252. Basore I 71, 241. Miller 240. Basore II 247, 251 (probably PD, not confirmed).
- Tanakh: 160 (JPS 1917, edited).
- Bible: 8 and 140 (same wording in KJV).

That's about 20 lines. Every other quote needs replacing or a licence:
- ESV: 64 lines. Its terms add a trademark condition and a no-AI-processing clause.
- Saheeh International: 31 lines, all rights reserved.
- NJPS 1985 and NASB.
- Bodhi (NC-ND), Thanissaro (NC), Access to Insight/BPS (free distribution).
- Feng & English, Mitchell, Watson, Lau, Mair, Hays, Costa.
- Thich Nhat Hanh, Suzuki, Byrom, Dalai Lama.

About 65 lines also have a wrong reference, a misattribution or no source, and need fixing whatever the licence. Options A/B/C are in §3 of the 11-23 record. Pricing (commercial or not) affects the NC and free-distribution terms.
