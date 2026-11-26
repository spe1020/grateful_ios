---
title: "Grateful Day: Account Isolation Recommendation (web #44, iOS #27)"
tags: [grateful-day, privacy, account-isolation, product-recommendation]
status: active
created: 2026-11-24
---

# Account isolation: product and privacy recommendation

Prep, 2026-11-24. Source: Seth's Phase 1 handoff (#general, event 38e89e0d). Both issues are Seth decisions. This is a recommendation, not approved work.

**The principle both issues break:** whatever belongs to an account goes with that account and nowhere else. Its reflections go to its own relays, and it doesn't inherit anything from another identity that used the same device. That is already the rule on iOS (Chief P17, M5 flows doc). The two bugs are the gaps in it.

## iOS #27: bind at creation (Option 1)

**Recommendation:** a reflection saved while an account is connected belongs to that account from the moment it's saved. Only rows written with no account connected (guest) can ever be adopted.

**Why:**
- **We already promised it.** The F7 sign-out sheet says unsaved reflections "will be saved when you sign back in with the same account." Today D adopts and publishes them, so that sentence is false. Binding at creation makes it true.
- Words written as C, published as D, with metadata (date, save time, length) made public under D's identity. Encryption doesn't fix that. It's a trust failure, not an edge case to explain away.
- The app can't tell "guest" from "C, not yet published" afterwards, so the only safe time to record ownership is at save.

**Options:**
- **Option 2 (record the writer separately)** gives the same product behaviour. Engineering can pick 1 or 2, but there must be one rule: a row is guest only if no account was connected when it was written. Product leans to Option 1 because it's one concept, not two.
- **Option 3 (ask at sign-out)** is not needed. F7 already counts the unsaved rows, and once rows are bound its copy is accurate.
- **Option 4 (keep it and disclose it): rejected.** Copy can't make publishing under the wrong identity acceptable.

**Required behaviour:**
1. Saving while connected stamps the connected account, whether or not the disclosure has been accepted and whether or not a publish pass has run.
2. Saving while signed out stays ownerless (guest), and the existing first-connect adoption and spec B review apply.
3. After C signs out, C's unpublished rows show as "From another account" (the existing display rules). They're never adopted, edited or published by D.
4. When C reconnects, its unpublished rows publish as normal.
5. `pendingCount`, the Saving mark and the F7 and F8 counts include C's bound but unpublished rows when C is connected. F8 keeps counting every row.
6. Every publishing safeguard is unchanged: refetch before send, the unresolved gate, and archive before replace.

**Copy:** none new. The existing "From another account" lines and F7 already cover it. If C's unsaved rows are shown under D, the existing label text ("isn't saved to the account you're using now") is accurate.

**Regression tests:**
- Connect C, write, sign out before any pass, connect D, accept the disclosure, run a pass. Nothing is sent, and the row stays C's and read-only.
- The same, but C reconnects. The row publishes under C.
- Write signed out, then connect D. The row is adopted by D (unchanged).
- D's disclosure count excludes C's rows.

## Web #44: relay list per account

**Recommendation:** answers to the issue's five questions.
1. **Per pubkey: yes.** Store relay lists by pubkey. An account with no kind 10002 uses the app defaults, never the last account's list.
2. **On logout or switch:** drop the previous list immediately. Reads may use defaults while the new account's lookup runs. **Writes wait** until the lookup resolves (found, or confirmed none, in which case use defaults). This matches the iOS unresolved gate. While waiting, entries show their normal saving state, not an error.
3. **Manual edits belong to the account,** not the browser. B never sees or uses C's edits.
4. **Migration:** the single stored key can't be attributed reliably, so it isn't carried over to any account. On the next login, fetch kind 10002 as normal. The cost is that a manual, unpublished edit is lost once. That's acceptable at this stage.
5. **Hold writes until resolved: yes** (the same as 2). The base-version check and the settings read-merge-write must use the signed-in account's resolved list.
- Also: compare `updatedAt` only within one pubkey.

**Privacy rationale:** sending B's events to C's relays lets those relays link the two identities by connection and timing. People keep separate identities precisely so that can't happen.

**Regression tests:**
- C (has a list) logs out, then B (no list) logs in. B reads from and writes to the defaults, and nothing goes to C's relays.
- B's list is older than C's. B's list is used.
- Switch accounts. No publish happens before B's lookup resolves.
- A manual edit under C isn't present under B.
- With the legacy single key present, it isn't applied to whoever logs in next.

## Decisions for Seth
1. #27: approve binding at creation (architectural change to storage design r3.1).
2. #44: approve per-account lists, writes held until the lookup resolves, and dropping the legacy key on migration.

## Approved 2026-11-24 (Seth, event 6df124c6)
Seth approved #27 (owner at write time, plus the sign-out count and copy fix), #44 (per-account relay lists, with ambiguous legacy config dropped) and the web author-validation PR. Prep verifies the account-switching and sign-out experience on each PR.

### F7 sign-out copy, corrected (replaces the "unsynced" line in the M5 flows doc)
**Count:** reflections owned by the connected account that aren't "Saved to your account" (fewer than 2 acks). If their sync state can't be read, count all of that account's reflections. Synced days are never counted. Guest rows are counted separately.
- Owned and unsaved (N > 0): "**N reflections** haven't been saved to your account yet. They'll stay on this iPhone and will be saved when you sign back in to this account. They won't be saved to any other account."
- Guest and unadopted (M > 0, shown only when M > 0): "**M reflections** written before you signed in haven't been saved yet. They'll stay on this iPhone and can be added to the next account you sign in with."
- Neither: no count line. The "Always" line and the backup lines are unchanged.

### Experience checks Prep will run on the PRs
1. Connect C, write, sign out before any pass, connect D. Today is empty for D, with the line "You also wrote today under another account." C's text opens read-only, never in D's editor, and D's disclosure count excludes it.
2. If D already has that day, D's entry is untouched and nothing is set aside as a conflict copy.
3. C reconnects. The row is C's again and publishes.
4. The sign-out sheet matches the counts above. It shows no count when everything is saved.
5. Web: C, then logout, then B (no list). B sees the defaults in relay settings, nothing from C. Saving relays as B never shows or publishes C's relays. While the lookup is pending, saving shows the normal saving state and no error.

## Prep verdicts
- **Web #47 (#44) at baa7e27, 2026-11-24:** PASS from reading the code, with one required copy fix: Relay settings needs the line "Loading your relays… You can edit them once they've loaded." while the status is unresolved. Optional nit: a reason-specific message for RelayAccountChangedError. Check 5 in a real browser is still open, waiting on Chief to say who runs it.
- **iOS #27:** pending.
- **Web #47 check 5 at ce03779 (the SHA Audit passed), 2026-11-25:** PASS in headless Chromium with throwaway C and B. After B logged in, 0 frames went to C's relays, and B's save reached the defaults only. The relay settings step was N/A: RelayListManager isn't mounted in the app.
- **iOS #29 (#27) at cbf8f67:** PASS from a code and copy read. Copy fix for Sous: the singular forms say "They'll" with "1 reflection" and need "It'll"/"It won't". Agreed with Chief's scope ruling that a guest day edited while connected becomes that account's. The D Today line still needs checking on a device.
- **iOS #29 copy at b3c1096, 2026-11-25:** PASS. 8786da4 gives both singular sign-out lines "It'll stay … It won't be saved" (plural unchanged), and testSignOutCopy asserts both singular strings. b3c1096 touches only OwnerAtWriteTests (Audit's probes). Code verdict remains Audit's.
