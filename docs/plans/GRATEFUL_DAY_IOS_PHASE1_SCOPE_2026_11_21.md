---
title: "Grateful Day iOS — Phase 1 Scope, Flows and Acceptance Criteria (Prep)"
tags: [grateful-day, ios, phase-1, product, acceptance-criteria]
status: active
created: 2026-11-21
---

Source of direction: Seth, #general kickoff event 66ee125b (2026-11-21), which authorizes Phase 1 plan + build.
Source of truth: PLANS/GRATEFUL_DAY_IOS_MVP_RECOMMENDATION_2026_11_21.md (the MVP). This doc does not add requirements. It splits the MVP into increments, adds the user flows, and gives each increment checkable criteria. If the two docs disagree, the MVP doc wins, and Prep fixes this one.
Also binding: interop spec PLANS/GRATEFUL_DAY_36669_30078_INTEROP_SPEC_2026_11_21.md (r4), storage recommendation PLANS/GRATEFUL_DAY_IOS_STORAGE_BACKUP_RECOMMENDATION_2026_11_21.md.
Baseline: grateful_ios main @ a53a4c9 (Phase 0 merged: NostrCore, GratefulDayCore with 36669 codec, notes, local day, deletion, 30078 settings, bundled wisdom). Web reference: gratefulday @ a33f42c.

## One sentence
A quiet place to write what you're grateful for each day, with one piece of wisdom to start you off, that stays yours.

## Numbering
**Uses Chief's confirmed M1–M6** (PLANS/GRATEFUL_DAY_IOS_PHASE1_PLAN_2026_11_21.md). Prep's earlier P1–P7 draft is withdrawn: wisdom stays in M4 and conflicts in M6, per Chief. One condition from Prep, which Chief's plan already covers: **M5 must not be released to users without M6.** Connecting without fetch-first and the conflict review is the silent overwrite the MVP forbids. M5 and M6 can be separate PRs, but they ship together.

## Design direction (applies to every milestone)
- **Calm.** One primary action per screen. No badges, red dots, pressure counters or confetti.
- **Native iPhone.** SwiftUI, system navigation and controls, Dynamic Type, Dark Mode, iOS 17 minimum, iPhone only.
- **Words.** "Reflection" for what the user writes; "Grateful Day" in two words. No "streak", "secret key" or "nsec" anywhere a guest can see. No "private" or "only you can read it" outside MVP spec A's exact copy.
- **Saving never waits.** No spinner between typing and saved.

---

## M1 — App shell; first launch lands on Today
**User flow:** open app → Today: today's date, a calm empty writing area (not yet active), and room reserved for the day's wisdom (filled in M4). Calendar and Settings are reachable with simple placeholder screens.

**Acceptance:**
1. Cold launch lands on Today, with no sign-in, onboarding wall, permission prompt or network request.
2. Works in Airplane Mode on first launch.
3. Navigation to Today, Calendar and Settings uses standard iOS controls, and each one is reachable in one tap from any other.
4. Design foundation (type scale, colours, spacing) uses Dynamic Type and supports Dark Mode. Today renders without clipping at the largest accessibility text size, in both light and dark.
5. VoiceOver can reach and name every control. Today's date is read first.
6. No network code, analytics, tracking or third-party SDKs in the app target. No key or account code (keeps M1–M4 out of Seth's gate).
7. Depends on the Phase 0 packages; no new dependencies. Green on the CI Xcode 26 runner (Chief P7).

## M2 — Guest journal storage + pre-account statement
Mostly invisible to users. What they see is the honest statement; what matters is that nothing is ever lost.

**Acceptance:**
1. **Saved means saved.** A stored entry survives backgrounding, force quit and device restart. Test: write, kill the app within ~1s of the last change, relaunch, text intact. Sous states the actual drop window in the PR; the product ceiling is about 1s of typing.
2. One entry per local date (Phase 0 day key). Notes are stored as blank-line-separated plain text, matching `EntryNotes`. A stored entry can later become a valid 36669 event with no change to its date or text. Covered by a test that encodes a stored entry with Phase 0's codec.
3. **Storage protection (Seth's rule):** the store and any future unsynced queue are excluded from iCloud and iPhone backups, re-applied every launch, with complete file protection and CloudKit off (storage recommendation §1–3, §7). Audit verifies. Real-device-only checks (Quick Start transfer, SQLite sidecar protection) stay an open [verify] item and don't block the merge, per Sous.
4. **Never show an empty journal by mistake.** If the store can't be opened (device locked, protected data unavailable, open error), the app shows a calm locked or retry state, never an empty Today or Calendar. It never creates a fresh store over an existing one.
5. A failed write keeps the text in memory and shows "Couldn't save just now. Your text is still here." It never discards text.
6. Each entry stores a private-by-default flag. There's no toggle in guest mode, since nothing publishes. The model can hold what M5/M6 need (deletion tombstone, sync state) without a destructive migration later.
7. **Pre-account statement**, exact copy from the MVP doc ("Local drafts are not backed up"), is in Settings → Privacy and one tap from Today.
8. **Local status label:** an entry's state reads "On this iPhone only" (Chief P3). No synced state until M5.
9. No surface claims backup, safety or recovery for local reflections.

## M3 — Write/edit today, calendar, delete, counts
**User flow:** on Today, tap the writing area → type → it saves as you go. A blank line starts a new note. Calendar → month view with days that have reflections marked → tap a past day to read it. Future days can't be opened.

**Acceptance:**
1. Typing on Today saves automatically with no save button and no spinner (meets M2 #1).
1a. **Writing-area wording (Prep ruling 2026-11-21, after Seth event e2dc1f93):** drop the visible "Today's reflection" label from M1. The date and the Today tab already say "today", and a permanent label above the text the user writes is clutter. Instead, the empty editor shows placeholder text, **"What are you grateful for today?"**, which disappears once they start typing. "Today's reflection" stays as the editor's VoiceOver label (not visible), so assistive tech still names the field. Growth may tune the placeholder wording.
2. Today stays editable until local midnight. If the app is open at midnight, Today moves to the new date, and text being written isn't lost: it stays with the date it was started on.
3. **Length cap:** near 65,535 bytes, the calm note "This day's reflection is nearly full." At the limit, input stops. Typed text is never cut on save.
4. **Delete today's reflection:** confirm "Delete this reflection? This can't be undone." [Delete] [Cancel]. Local delete, recorded so M5 can apply web's NIP-09 semantics later.
5. Calendar marks days with a reflection, without relying on colour alone. Past days are read-only, with no edit control (web `isPast`). Future days are disabled and announced as unavailable by VoiceOver.
6. Counts practice: "12 reflections this month" plus a total. No streak number, and no string from web's `StreakBadge` or `MilestoneCelebrationDialog`.
7. Milestones on totals only (1st, 7th, 30th, 100th, 365th): a quiet one-line acknowledgement, shown once. (Fewer milestones than web is still open for Seth. Build these five; adding more later is a copy change.)
8. After a gap of 2+ days, Today shows "Welcome back." Never a reset or "you missed" message.
9. A month with a full year of data opens in under ~0.5s on the oldest device Sous tests on.

## M4 — Wisdom, "Reflect on this", calm first launch, reminder
**User flow:** Today shows the day's wisdom above the writing area: passage, author/source, Grateful Day reading, one question. "Reflect on this" pins the question above the writing area. No separate first-launch line: the M3 placeholder already does that job, and two near-identical invitations on one screen is noise (Prep, 2026-11-21). After the 2nd saved reflection, offer once: "Want a gentle reminder each day?" [Choose a time] [Not now]. It's also in Settings.

**Acceptance:**
1. The wisdom shown for a local date is the same item web shows (rotation from `lib/wisdom.ts`), from the bundled `wisdom.json` via Phase 0's `WisdomLibrary`. Tested across a year boundary. Works offline. Wisdom text isn't rewritten.
2. "Reflect on this" never inserts text into the entry.
3. VoiceOver reads date, passage, author, question, in that order. The passage doesn't clip at the largest text size.
4. A new user can save a first reflection within 30 seconds of first launch, with no account and no permission prompt. No carousel and no account step.
5. Notification permission is requested only after the user picks a time. One daily local notification, off until opted in, no server push. Changes take effect immediately.
6. The connect prompt is not shown until M5 ships.

## M5 — Account (key) and connect — Seth gate
**Scope:** "Create a journal key" (new) and "Use my Nostr account" (existing). How the existing account is used (import vs. remote signer) and how a new key is kept safe (MVP item 8) is Sous + Audit's design. Product requirement: a person can keep their key safe and restore on a new iPhone in one understandable step, without knowing what a key is.

**Gate:** the key-backup design needs Seth's review before it is built (his "no unreviewed backup or recovery mechanism" rule; delegation log item 10). Keychain decisions from the storage recommendation stand (this-device-only, survives reinstall, explicit "Remove key from this iPhone").

**Acceptance (product side; Audit owns the security criteria):**
1. No key, nsec or "secret key" screen before the first saved reflection, ever.
2. A new user can create a key and complete the safety step in under a minute, in plain words.
3. Signing out with unsynced reflections warns first: "X reflections are only on this iPhone and will be lost." [Keep them] [Sign out anyway].
4. No profile, avatar or bio fields.

## M6 — Sync, conflicts, Set aside — ships with M5
Built exactly to MVP spec A (disclosure sheet), spec B (connect without overwriting), and the interop spec. Not restated here, so there's one source. Key acceptance criteria, all from those specs:
1. Fetch first, publish last. If the fetch fails or is incomplete, nothing publishes: "We couldn't reach your journal yet. Your reflections are safe on this iPhone."
2. No reflection publishes before the disclosure sheet is accepted for this account on this device. "Not now" publishes nothing and loses nothing.
3. Conflicts: one review screen, "Keep both" default, keep-one sends the other text to Set aside (never auto-purged), "Keep both for all", private wins.
4. Every word written on the phone ends up published or in Set aside.
5. Undecryptable remote day: "We can't open your reflection for <date> on this iPhone. What you wrote here is kept." Never treated as empty.
6. Unparseable decrypted 30078 settings are never treated as empty or overwritten (interop spec r4 §2.4).
7. Public toggle per entry with the two one-line notes from spec A.
8. Unsynced days carry the "not backed up yet" mark, and retries are quiet.
9. Web shows the phone's entries afterwards, and keeps all of its own entries and settings.
10. Delete after connect publishes NIP-09 with the same semantics as web.

**Out of scope (per MVP):** account switching, merging two accounts, reconciling deletions made on web while offline.

## M6 (cont.) — Refinement
Full VoiceOver and Dynamic Type pass, Reduce Motion respected, regression suite across M1–M6, performance check with 3+ years of entries. Only fixes and polish. New behaviour goes back through Prep.

---

## Not in Phase 1 (unchanged from MVP)
Social feed, comments, reactions, sharing, zaps, wallet, DMs, notifications bell, payments, profile editing, relay manager, export, wisdom history, iPad layout, widgets, Apple Watch.

## Open for Seth (none block M1–M4)
1. Key-backup design review (blocks M5 build).
2. Fewer milestones than web (M3 builds five on totals).

## How Prep validates
Each PR states which criteria it covers. Prep checks the built behaviour against them, in the simulator or from the PR's screenshots and recordings, and reports met, gap, or new-request (a new request is not a blocker). Prep's acceptance is one of Chief's merge conditions. It doesn't replace Audit's PASS.

## App icon (Seth supplied, event 353f3d7f, "Minimalist layered hills at sunrise", 1254×1254 PNG)
Prep's product requirements. Prep could not view the image because Buzz media is blocked for Prep, so this covers fit, not art direction.
1. Ship it as its own small PR: no code, and not folded into M2, which keeps M2's storage review focused.
2. A single 1024×1024 opaque PNG (no alpha) in the asset catalog. Scale the source down; don't crop off key elements.
3. No pre-rounded corners, border or shadow: iOS applies the mask. The key shapes (hills, sun) stay inside the centre ~80%, so the corner mask doesn't clip them.
4. Readable at home-screen and Settings/Spotlight sizes. Attach a screenshot of the simulator home screen in light and dark.
5. No dark or tinted variants for MVP (iOS 17 minimum). On iOS 18 and later, the system handles tinting.
6. The art is unchanged. Any redraw is Seth's call.

## M2 copy review (Prep, 2026-11-21, Seth event 35ef16eb; reviewed at main 584a4a2)
- **Locked** "Unlock your iPhone to open your journal.": approved as is.
- **Try again**: approved as is.
- **Save failed** "Couldn't save just now. Your text is still here.": approved as is (this is the MVP copy).
- **Open failed**: change "Your journal couldn't be opened just now." to **"Your journal couldn't be opened just now. Nothing has been deleted."** On a journaling app, the first fear is lost entries. "Nothing has been deleted" is the strongest claim the code supports: the store is never replaced, and Audit's corrupt-store test checks it byte for byte. Don't say "safe" or "secure", per Seth's rule not to promise more than we can verify.
- **If Try again fails again**, add a second line: "If this keeps happening, try restarting your iPhone." This gives the user a next step, not a dead end. A support or contact path is a later decision, not an MVP one.
- Ships in M3a. No push needed to the merged #7. Growth may tune the wording if the facts stay the same.

## Alternate pre-account statement when backup exclusion failed (Prep, 2026-11-21; Chief P10, event 4b558809)
Replaces the whole pre-account statement, wherever it appears (Settings → Privacy and the "On this iPhone only" sheet), only while `backupExclusionFailed` is set. It goes back to the normal statement as soon as a retry succeeds.

> "Until you connect an account, nothing you write is published. Your reflections are saved on this iPhone. We weren't able to keep them out of iCloud and iPhone backups on this iPhone, so they may be included in one. We'll keep trying each time you open the app. If you lose or replace this iPhone, or delete the app, they may not be recoverable."

- It carries Chief's three facts: we couldn't exclude them, they may be in a backup, we'll keep trying.
- The last sentence reads "may not be recoverable", not "can't be". If a backup did capture the journal, "can't" would be false, and promising recovery would also be false.
- The "On this iPhone only" label stays: it still means not synced, which remains true.
- No banner, alert or badge: the failure is rare and the user can't fix it. The statement just stays accurate. Revisit if device testing shows it isn't rare.
- Growth may tune the wording if all four facts stay.

## Final journal copy, M3a follow-ups (Prep, 2026-11-21, Seth event e31994fc; reviewed at main 6f97711). Goes in M3b.
1. **Backup-exclusion failed:** the statement in "Alternate pre-account statement" above is final. Swap it in for Sous's placeholder exactly as written.
2. **Before the first exclusion check (Chief P11):** don't show the "failed" statement. Before the check, nothing has failed yet, so "We weren't able to…" would be a false claim the other way. Use a third, neutral statement, true in every state:
   > "Until you connect an account, nothing you write is published. Your reflections are saved only on this iPhone. If you lose or replace this iPhone, or delete the app, they may not be recoverable."
   Order: check not yet done → neutral; check succeeded → standard pre-account statement; check failed → failed statement.
3. **"Delete reflection"** (menu item): approved.
4. **"Couldn't delete just now."** → **"Couldn't delete just now. Your reflection is still here."** This matches the save-failed message and tells the user what state they're in.
5. **"Welcome back." trigger:** confirmed. It shows when the last reflection was 3 or more local days ago (2+ whole empty days), never for a brand-new user, and deleted days don't count. This matches `welcomeBackGap = 3`.
6. **Not yet in the app (checked main 6f97711):** the M2 copy review changes. Open failed → "Your journal couldn't be opened just now. Nothing has been deleted."; after a repeat failure, add "If this keeps happening, try restarting your iPhone." These go in M3b.

## M4 reminder copy review (Prep, 2026-11-21, reviewed at main 89a9a16)
All approved as is: notification title "Grateful Day" and body "A quiet minute of gratitude."; "Want a gentle reminder each day?" [Choose a time] [Not now]; "Daily reminder"; "One gentle reminder a day, sent by this iPhone. Nothing is sent from a server."; "Remind me at <time>"; "Turn off reminder"; "Notifications for Grateful Day are turned off in Settings." + "Open Settings". The body never includes reflection text (Audit verified). Growth may tune.

## Label for other accounts' days (Prep ruling for M5a)
Key design r3.1 labels these days "From your signed-out account". Use **"From another account"** instead (M5 flows doc, "Days from another account"). It's true both when signed out and when connected as B, and doesn't assume the reader owns the other account.
