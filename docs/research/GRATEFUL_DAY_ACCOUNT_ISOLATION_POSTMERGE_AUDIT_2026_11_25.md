---
title: "Grateful Day account isolation post-merge audit (iOS c9101349, web 9347018)"
tags: [grateful-day, audit, account-isolation, ios, web]
status: active
created: 2026-11-25
---

# Account isolation post-merge audit

Requested by Chief, event 34b024d2 (general, thread bc767b8f), from decision log P86.
Targets: iOS spe1020/grateful_ios main `c9101349` (#29 merged), web spe1020/gratefulday main `9347018` (#45–#49).
Both were reviewed in detached audit worktrees: REPOS/grateful_ios-audit and REPOS/gratefulday-wt-audit-pr49.

## Test 1 scope (recorded as requested)
Test 1 was USER-VERIFIED PASS by Seth on 2026-11-25. Its scope is identity C only, iOS→web, private (kind 36669 NIP-44), with web `9347018` live.
It is not evidence for any of these:
- account switching or isolation
- Keychain/iCloud recovery
- web→iOS
- deletion
- conflicts
- guest adoption
The iOS build Seth used is still pending from him.

## Paths read
iOS:
- JournalRepository save/delete/entry/signOutCounts
- FirstConnectSort
- SyncService run/publish/reset/stop
- GratefulDayApp onChange(activeOwner) → reset + isCurrent closure
- PublishPass isCurrent guards
- RemoteJournal author filter (DailyEntry.isValid owner)
- RelaySet.lookup
- RelayFetcher sig check (e.isValid)
- Outbox owner scoping

Web:
- AccountRelayProvider
- accountRelays
- NostrSync
- NostrProvider eventRouter gate
- AppProvider legacy drop
- DayDetailDialog seeding and save errors
- LoginPersistence cross-tab behaviour
- RelayListManager publish
- nostrify NRelay1 verifyEvent default

## Combined behaviour: holds
- Ownership is fixed at write time on iOS, and editing a guest row under an account reassigns it. FirstConnectSort adopts only live guest rows.
- Sign-out or switch on iOS calls sync.reset (relays, settings, deferral, unreachable memory). An in-flight pass is dropped by isCurrent after the reads and before every sign or send.
- Both clients accept only the account's own signed events: iOS through DailyEntry.isValid(owner) plus the fetcher's sig check, and web through #46 plus NRelay1's verifyEvent.
- Web: per-account relay slots, nothing is published while unresolved, and a waiting write is refused on switch. The legacy browser-wide list is dropped.
- Both clients use the same five default read relays. iOS writes to three of them with no list, web writes to all five, and both read all five, so the no-list case interoperates.

## Findings (coverage and residual risk; no confirmed defects)
- **L1, iOS coverage.** No test pins the App-level wiring: `onChange(account.activeOwner)` → `sync.reset()`, and an isCurrent closure built on `activeOwner == owner`. The unit tests inject `isCurrent: { false }` directly (SyncReadTests:89, PublishPassTests:377, RelayMemoryTests:130). If the wiring regressed, no test would fail. Fix: a SyncService-level test for "A connected, pass running, switch to B: no A import, no A send, relays nil", or a UI test.
- **L2, iOS coverage.** A guest row deleted while an account is connected stays a guest tombstone (delete does not reassign; FirstConnectSort skips tombstones). Under the next account, writing that day revives it as that account's. The behaviour is correct by reading, but no test pins it.
- **L3, web, suspected and reachability unverified.** DayDetailDialog keeps the open draft across a change of `user`. When the seeded key was `D:none`, the drafts carry into the next account's day and save under it. That is intended for guest→sign-in (tests :173, :189), but nothing distinguishes A→B. In-tab switching is behind the modal, and LoginPersistence adopts other-tab logins only when this tab has none. I found no path to it. There is no test that a draft started under A is not saved as B.
- **L4, web↔iOS, residual.** RelayListManager stores an edit locally, then publishes kind 10002. If the publish fails (toast shown), web keeps writing to the new list while iOS reads the old one from the network. Web→iOS would then miss entries. For the device run: don't edit relays on web before web→iOS.
- **Info.** The known limitations already accepted by Seth are unchanged: pre-#29 ownerless rows have no migration, a web list only on non-default relays isn't found, and DM gift wraps fail closed.

## Verification
- Web `9347018`: `npx vitest run` with NODE_OPTIONS=--no-experimental-webstorage gives 46 files and 483/483 passed.
- iOS `c9101349`: GratefulDayTests on simulator 31D4621F, derivedData .scratch/iso-c910: 315 executed, 1 skipped, 0 failures (TEST SUCCEEDED), HEAD c9101349 confirmed in the same shell.

## Assessment
PASS for account isolation within this scope. There are no confirmed defects. L1–L4 are Low, and are coverage or residual items for Sous to schedule. None blocks Phase 1.

## Ruling: remote deletion of an unedited day (Chief, event 1f60ab58)
**Intended, and not a data-preservation gap.**
- `RemoteImporter.swift:94-96`: when another device's kind 5 reaches a day with no pending edits, the text is first archived as an `EarlierVersion(.replacedByRemote, surfaced: false)`, and only then is the row tombstoned. The text is kept in the store, and nothing purges it.
- `setAsideVersions()` lists only `surfaced` versions (JournalRepository.swift:295), so it never shows in Set aside. That's why Ship saw nothing there.
- A day with pending edits becomes a §4.2/§7 conflict instead, and the person chooses on the conflict screen.
- The test pinning this is `RemoteImportTests.testRemoteDeleteTombstonesAndArchives`:190. It checks the archive, not visibility.
- Why this is acceptable: the deleted text was already published from this account. The deletion is the account's own signed act. A local delete on iOS keeps no copy at all. Surfacing applies to text lost through replacement (P22), not to a deliberate deletion.
- Residual (Info, Phase 2 candidate): kept copies have no UI. A wrong deletion from another device, or by a stolen key, can be undone only by a developer. A "recently deleted" view would expose them.
- For the run sheet: Ship's approach stands. Deletion PASS is "the day disappears on iOS, and nothing is in the conflict list". Test Set aside through a web replacement.
