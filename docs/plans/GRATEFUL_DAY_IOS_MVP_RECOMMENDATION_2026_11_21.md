---
title: "Grateful Day iOS — MVP Recommendation (Prep)"
tags: [grateful-day, ios, mvp, product]
status: active
created: 2026-11-21
---

Source of direction: Seth, #general thread 427ef026, event ed2f849d (2026-11-21).
Reference read: ~/.buzz/REPOS/gratefulday @ a33f42c (read-only). Chief frame: PLANS/GRATEFUL_DAY_IOS_DISCOVERY_FRAME_2026_11_21.md.
Status: **FINAL product recommendation (Prep, 2026-11-21)** — the product input Phase 0 builds against. Not Seth-approved; items marked SETH below stay his.

## Final calls (Prep, 2026-11-21)
1. **Conflict screen** — one review screen, "Keep both" default per day (combined as notes, existing first), keep-one alternative sends the other text to "Set aside" (never auto-purged), "Keep both for all" shortcut, private wins. Spec B §4.
2. **Public → private warning** — one non-blocking line under the toggle, every time: "Earlier public versions may still be readable. Making it private protects what you save from now on." Spec A.
3. **Disclosure before account link** — one sheet, before anything publishes: heading "What's private in your journal", count line, "Your words are encrypted, so they can only be read with your key." / "The dates and times you save or edit entries can be seen by others." [Continue] / [Not now] / Learn more. Once per account per device; mirrored in Settings → Privacy. Spec A. Supersedes Growth's draft heading and "only you can read them".
4. **Minimum iOS** — iOS 17.
5. **Local drafts in iCloud/device backup** — **EXCLUDED (Seth decided, event fa4a61ce).** Prep's earlier "include" recommendation is withdrawn. What it means for users, and the copy, is in "Local drafts are not backed up" below.


> **Chief note, 2026-11-21 (RESOLVED: Prep incorporated this below):** Seth decided (#general event fa4a61ce) that the MVP **excludes unencrypted local drafts from iCloud backups** until a privacy and recovery approach is established and verified. That supersedes the "include" recommendation in items 5, 64 and 167. Prep still needs to write up what this means for users, especially that reflections not yet synced are lost if the phone is lost or replaced. Sous recommends the storage implementation, Audit validates it. No unreviewed backup or recovery mechanism.

## Local drafts are not backed up — what it means for users (Prep, 2026-11-21, after Seth's decision fa4a61ce)
**The fact users must understand:** a reflection that hasn't synced to an account exists only on this iPhone. It is not in iCloud or any iPhone backup. If the phone is lost, broken, replaced or reset, or the app is deleted, that reflection is gone and can't be recovered.

**Who it affects:**
- **Guests (no account yet):** their whole journal. This is the bigger exposure.
- **Connected users:** only reflections not yet synced (normally seconds; longer when offline or relays are blocked). These carry the "not backed up yet" mark.

**Product response — honesty, not new features.** No new backup or recovery mechanism (Seth: none until reviewed). Connecting an account is the backup, and the copy says so plainly.

**Copy (final for in-app; Growth may tune wording if every surface keeps the same facts):**
- **Pre-account statement** (Settings → Privacy and the Today footer link; replaces the earlier pre-account line):
  "Until you connect an account, nothing you write is published. Your reflections are saved only on this iPhone and aren't included in iCloud or iPhone backups. If you lose or replace this iPhone, or delete the app, they can't be recovered."
- **Connect prompt** (after the 3rd saved reflection, dismissible, returns at most once a week; never before the first reflection):
  Heading: "Keep your reflections safe" · Body: "Right now they're only on this iPhone. Connect an account to back them up and use them on other devices." · [Connect] [Not now]
- **"Not backed up yet" mark** (per day, connected users): tap shows "This reflection is only on this iPhone until it syncs. We'll keep trying."
- **Before deleting the app / signing out** (in-app sign-out only; iOS gives no hook on app deletion): if any reflection is unsynced, "X reflections are only on this iPhone and will be lost." [Keep them] [Sign out anyway].
- **Learn more page:** replace Growth's "Before you connect an account" bullet with: "Before you connect an account, your reflections stay on this iPhone only. They aren't in iCloud or iPhone backups, so they're lost if the phone is."
- **App Store / FAQ:** no "never lose an entry" or "your journal is always safe" claims.

**Acceptance:**
1. Local drafts and the unsynced queue are excluded from iCloud and iPhone backups (Sous implements, Audit verifies, including whether direct iPhone-to-iPhone transfer carries them; copy assumes it does not).
2. A guest sees the pre-account statement in Settings → Privacy and can reach it from Today in one tap.
3. The connect prompt never appears before the first saved reflection and never blocks writing.
4. Every unsynced day shows the mark; in-app sign-out with unsynced reflections warns first.
5. No surface claims backup, safety or recovery for unsynced reflections.

**Success measure changes:** "Never loses an entry" becomes **"Never loses a synced entry, and never loses an unsynced one without having told the user first."**

**Revisit when:** Sous + Audit have a reviewed encrypted local-backup approach. Then Seth decides whether to include drafts.

## One sentence
A quiet place to write what you're grateful for each day, with one piece of wisdom to start you off, that stays yours.

## MVP — in
1. **Today** — today's wisdom (passage, Grateful Day reading, one question) and the writing space. Opening the app lands here.
2. **Write and edit today's reflection** — one or more notes per day (blank-line separated, matches web `entryNotes.ts`). Editable until local midnight.
3. **Calendar / past reflections** — browse the year, open any past day, read it. Past days read-only (matches web: `DayDetailDialog` gates edits on `isPast`). Future days locked.
4. **Daily wisdom** — same rotation and schedule as web (`lib/wisdom.ts`), bundled in the app so it works offline. "Reflect on this" carries the question into today's entry as context, never auto-inserted.
5. **Count practice, not perfection** — headline is reflections written ("12 reflections this month", total days). No streak-loss copy anywhere ("Write today to keep your streak" is not ported). Returning after a gap gets a warm welcome back, never a reset message. Milestones mark totals (1st, 7th, 30th, 100th, 365th reflection), not unbroken runs. (Adopted from Growth's review, RESEARCH/GRATEFUL_DAY_IOS_POSITIONING_REVIEW_2026_11_21.md.)
6. **Private by default, always** — every entry is NIP-44 self-encrypted unless the user turns it public, regardless of signer. Verified at `a33f42c`: web seeds Private only when the signer confirms NIP-44 support, and defaults Public for bunker signers (support 'unknown') and signers that can't encrypt (`src/components/DayDetailDialog.tsx:336-341`). On iOS the app controls the signer, so private-by-default has no exceptions. Public is a deliberate per-entry choice.
7. **Write without an account** — see offline-first below.
8. **Key backup and recovery** — required in MVP (Audit requirement; product agrees). Whoever connects with a new key gets a simple, one-step way to keep it safe and restore it on a new iPhone, without needing to understand keys. Mechanism is Sous + Audit's.
9. **One daily reminder** — a local notification at a time the user picks, off until they opt in. No server push.
10. **Delete an entry** — required for trust.

## Seth's decisions, round 2 (2026-11-21, event 94d7a25d)
- **Option A**: keep the web format (36669 + kind 30078 settings). Content encrypted; dates and save/edit times stay public. Users must understand this before their first private reflection is published.
- Offline-first approved. Connecting an account fetches existing entries, surfaces conflicts, preserves writing. No silent overwrites.
- Prep's position: adopt Audit's approach. Entries are **plain local drafts until a key exists**. Nothing is signed or published before the user connects.

## Experience spec A: what "private" means (Prep)
**When:** the first time any reflection is about to be published from this device for this account. Because drafts are local until an account exists, that is the moment of connecting (or the first save after connecting). Never during first launch or first write.

**What:** one sheet, one screen, no scrolling.
- Canonical sentence (Prep confirmed Growth's wording, 2026-11-21; every surface derives from it): **"The words you write are encrypted. The dates and times you save or edit an entry can be seen by others."**
- Sheet copy (final for in-app; source PLANS/GRATEFUL_DAY_IOS_PRIVACY_COPY_DRAFT_2026_11_21.md):
  - Heading: **What's private in your journal**. Not "share", because "share" means public everywhere else in the app.
  - Count line, when connecting: "**23 reflections** will be backed up to your account." (Linking publishes the whole local journal at once, per Audit; the sheet sits before that step and says so.)
  - "Your words are encrypted, so they can only be read with your key." (Changed from "only you can read them" per Audit/Chief: true only while the key is safe; no forward secrecy.)
  - "The dates and times you save or edit entries can be seen by others."
  - [Continue] primary · [Not now] secondary (publishes nothing) · "Learn more" text link.
- Shown once per account on this device. The same text lives permanently in Settings → Privacy.

**Also:**
- Making an entry public shows one line under the toggle, every time: "Anyone can read this reflection." No extra confirm sheet, because the choice was already deliberate.
- **Public → private on an entry that was already published publicly** (Audit MEDIUM): one line under the toggle at that moment: "Earlier public versions may still be readable. Making it private protects what you save from now on." Shown every time; no blocking sheet. Today's entry only, since past days aren't editable in MVP.
- **Learn more page** must list everything visible: dates and save/edit times, approximate length of each entry, and that earlier public versions can persist. Also says that anyone who gets the key later can read the whole history, which is why key backup matters.
- **Length cap** (Audit LOW: NIP-44 max 65,535 bytes per entry): near the limit, a calm note "This day's reflection is nearly full." At the limit, input stops. Typed text is never dropped or cut on save.
- No other "private" wording appears in the app.

**Acceptance:**
1. No reflection is published before this sheet has been accepted for the account on this device.
2. "Not now" publishes nothing and loses nothing. The user can still keep writing locally.
3. Settings → Privacy shows the same two statements.
4. Before connecting, the only claim is the pre-account statement in "Local drafts are not backed up" above. (Superseded 2026-11-21: drafts are excluded from backups per Seth.)

## Experience spec B: connecting an account without overwriting anything (Prep)
**Two entry points, same flow:** "Create a journal key" (new) or "Use my Nostr account" (existing). Offered from Settings and from a gentle prompt after a few reflections. Never forced.

**Flow:**
1. **Fetch first, publish last.** Load the account's existing 36669 entries and 30078 settings before anything is published.
   - If fetching fails or looks incomplete, stop. Publish nothing and show: "We couldn't reach your journal yet. Your reflections are safe on this iPhone." Retry later. Sous and Audit define what counts as "complete enough".
2. **Privacy sheet** (spec A), if it hasn't been accepted yet.
3. **Sort by date:**
   - Local only → publish, encrypted by default.
   - Remote only → appears in the calendar. Nothing to do.
   - Both, same text → nothing to do.
   - Both, different text → a conflict.
4. **Conflicts.** One review screen: "You wrote on 3 days in both places."
   - Default per day: **Keep both**. The two texts are combined as separate notes in one entry, existing first, then this phone's.
   - Alternative per day: keep one. The other text is still kept in a local "Set aside" list and is never deleted silently.
   - A "Keep both for all" shortcut covers many conflicts.
   - A combined entry takes the more private setting of the two (private wins) and says so.
5. **Settings (30078).** Merge using the web rules (Sous's spec). Celebrated milestones and other synced state are never reset or overwritten by the phone's local copy.
6. **Publish** only after the review is finished.
   - Cancelling at any step leaves everything local and publishes nothing.
   - Publish failures retry quietly, with a small "not yet backed up" mark on the affected days.

**Out of scope for MVP:** merging two Nostr accounts, switching accounts, and resolving deletions made on web while the phone was offline. Sous and Audit flag the deletion case. If it's material, I'll revisit.

**Acceptance:**
1. Connecting an existing account that already has entries never changes or removes an existing remote entry without an explicit user choice on that date.
2. Every word written on the phone ends up either published or in "Set aside". Nothing disappears.
3. Cancelling or failing at any step leaves zero published events and all local drafts intact.
4. After connecting, web shows the phone's entries and still shows all of its own prior entries and settings.
5. A first-time user creating a new key goes through no conflict screen.

## Growth's four conflicts — resolved in this MVP (Seth asked, 2026-11-21, event 23dae195)
All verified against `a33f42c`.
1. **Streak pressure** (`StreakBadge.tsx:25` "Write today to keep your streak"; `MilestoneCelebrationDialog.tsx:52` "Two hundred days without missing one") → item 5: count reflections, totals-based milestones, warm return after a gap. Neither string is ported.
2. **Privacy claim exceeds reality** (text encrypted, date/day-of-year public) → no "private" or "only you can read it" claims in app or store copy until Audit rules on metadata; then copy states exactly what is protected and what isn't.
3. **Private not always default** (`DayDetailDialog.tsx:336-341`) → item 6: private by default for every entry, no signer exceptions.
4. **Onboarding starts with an account** (`auth/SignupDialog.tsx:60` "Your Secret Key is Ready!", then key download, avatar, bio) → item 7: first launch opens on Today; no key, avatar or bio before the first saved reflection. Profile fields aren't in the MVP at all.

## Seth's decisions applied (2026-11-21, event 23dae195)
- No payments, subscriptions or entitlements in MVP.
- Working positioning: "A quiet minute of gratitude, every day." Opening screen = today's wisdom + writing, which is that promise.
- Name: **Grateful Day** (two words) in all customer-facing copy.
- Usage numbers: unknown; no assumptions.

## Later (phase 2+, evaluate on evidence)
- Community feed, comments, reactions, replies — needs moderation, which is a product of its own.
- Share the day's **wisdom card** (image/text of the passage, never the user's entry) — first social candidate for phase 2: spreads the app with zero privacy exposure (Growth's idea).
- "Share to Nostr" (kind 1 post of an entry) — after wisdom-card sharing, if asked for.
- Your Wisdom history view — low cost once wisdom ships; phase 1.5 if Today feels thin.
- Profile editing, relay manager — default relays, no UI in MVP.
- Cross-device sync of wisdom history/milestones (NIP-78 path already noted in web docs).
- Export journal (PDF/text) — strong trust feature; early phase 2.

## Not porting (no plan to)
- DMs, notifications bell, zaps + NWC wallet, gifts, Gratitude Galaxy / Vine visualizations, Library.
These pull a journal toward a social/payment app. Revisit only if a later phase is explicitly social.

## Offline-first and no-account writing — product position
- **Recommend yes.** First launch goes straight to Today. No sign-up wall. Entries save on the device immediately.
- **The account is a backup/sync choice, not a gate.** Copy along the lines of "Keep your reflections safe across devices" — offered after a few entries, never before the first.
- **When they create or connect a key, existing local entries are kept and published** (encrypted by default). Nothing a guest wrote is lost. Web already preserves a guest draft on sign-in; iOS extends that to all local entries.
- **Saving never waits on the network.** Online, entries publish in the background; failures retry quietly with a small "not yet backed up" indicator, never an error blocking the write.
- **Honest about local-only:** before an account exists, Settings states plainly that reflections live only on this phone, aren't in iCloud or iPhone backups, and are lost if the phone is lost or replaced or the app is deleted. Exact copy: "Local drafts are not backed up" section.
- **Nonessential local data (Seth approved):** wisdom interactions, milestone-celebrated flags, reminder time stay on-device in MVP. Users lose nothing that matters (their writing) on a new device; they may see a milestone celebration twice. Acceptable.

## No-account key question (Chief raised) — superseded by spec B above; original requirements kept for reference
- The user never sees a key, nsec, or "secret key" screen before their first reflection is saved.
- Whatever is written before an account must end up in the user's eventual account with no duplicates and no loss, including when they later connect an *existing* Nostr identity that already has entries for some of the same dates (then: keep both texts for that day, merged as notes, never overwrite).
- Silent local key vs. unsigned local drafts is Sous + Audit's call. Product preference: whichever makes "back up" a single, understandable step later. If a silent key is chosen, the backup step must explain in plain words that losing the phone without backup loses the journal.

## Business model
Seth: not in MVP, not ruled out later. Product constraint if it's ever on the table: never paywall the writing or the user's access to their own entries. Sync/backup as a paid feature would conflict with "never loses an entry" and is not something I'd recommend.

## Product behavior Sous's kind 36669 spec must satisfy (Prep approves)
1. One entry per user per local date (`d`=YYYY-MM-DD); multiple notes = blank-line separated plain text, never JSON.
2. A local-only entry must become a valid 36669 event later without changing its date or content (data model must not block sync).
3. Edits to today replace the day's event; past days not edited in MVP.
4. Private = NIP-44 to self, `encrypted` tag, generic `alt`. iOS and web must each read the other's private and public entries.
5. Conflict rule needed (same day written on web and iPhone): newest wins is acceptable for MVP **only if** the losing text is never silently destroyed on the device that lost — Sous to propose; Prep reviews.
6. Deletion: NIP-09 plus local tombstone, same semantics as web.

## Privacy decision — DECIDED: Option A (Seth, event 94d7a25d); see spec A
Private entries still publish date, day-of-year and timestamp in public tags. That reveals *that* and *when* someone journals, not what. My product view: acceptable for MVP if disclosed in one plain sentence where the user turns on backup; Audit may recommend a stronger option (e.g. opaque d-tag), which would break web compatibility and needs a joint decision.

## Open questions (none block Sous starting architecture)
- Sign-in on iOS (generate key in-app vs. import nsec vs. remote signer) — Sous + Audit; product requirement: a new user can back up without understanding keys. Key backup UX is the single biggest product risk.
- Fewer milestones than web — Seth to confirm.

## Success, from the user's side
- Can write a first reflection within 30 seconds of first launch, no account.
- Never loses a synced entry, and never loses an unsynced one without having told the user first (was "never loses an entry"; changed after the backup exclusion).
- Returns because it feels calm, not because of streak pressure.

## Prep review of Sous's interop spec (PLANS/GRATEFUL_DAY_36669_30078_INTEROP_SPEC_2026_11_21.md, r2) — 2026-11-21
**Product behavior: approved**, subject to Audit's re-validation. §3–§4 match spec B. Answers to Sous's open items:
- **§4.3 Conflict UI:** Combine is the default ("Keep both"). Keep-mine/keep-theirs loser goes to the local archive, shown to users as **"Set aside"** (Settings → Set aside), readable and copyable, never auto-purged. Private wins; asking before anything public is right.
- **Undecryptable remote (§4.1 blocked):** user sees per day: "We can't open your reflection for <date> on this iPhone. What you wrote here is kept." No action required to keep writing other days.
- **Ongoing conflicts (§4.2):** same Keep-both default. In MVP these can only hit today's entry, since past days are read-only.
- **Remote deleted + local text → publish:** approved. Words written on the phone win over an older delete.
- **§1.8 time zones:** accepted for MVP. Travellers may skip or double a day. Since we count reflections, not streaks, the cost to the user is small.
- **§2.4 iOS-only synced settings:** none. Reminder time and other iOS preferences stay local. No second 30078.
- **iCloud / device backup:** ~~include local drafts in the standard iPhone backup~~ — superseded. Seth decided to exclude (fa4a61ce). See "Local drafts are not backed up".
- **Minimum iOS:** iOS 17 (Sous's proposal). Ship confirms.
- **Web changes (§8 #1, #2, plus Chief's settings fix):** product supports all three. Each one prevents real data loss. Seth decides.
