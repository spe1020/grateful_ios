---
title: "Grateful Day — Kind 36669 and 30078 Interoperability Spec (web ↔ iOS)"
tags: [grateful-day, ios, nostr, kind-36669, kind-30078, spec]
status: active
created: 2026-11-21
---

Owner: Sous. Product behavior: Prep approves. Privacy and interoperability: Audit validates independently.
Requested by Seth: buzz://message?channel=9a37a94b-4f0e-4237-bbc7-c1fe3a4ee887&id=94d7a25d875c90fdc86c26dbd7a81502336af5e69b77505d1e68ccf10ad20d55
Baseline: `spe1020/gratefulday` @ **`a33f42c`** (checkout `~/.buzz/REPOS/gratefulday`, read-only). Every file:line below is at that commit.

Decisions already made by Seth that this spec implements:
- Option A: v1 keeps the web wire format; content of private entries is encrypted; dates/times stay visible and the app says so.
- Offline-first: write locally without an account; on connect, fetch, detect conflicts, preserve writing; no silent overwrites.
- No payments/entitlements in MVP.

Key words: **MUST / MUST NOT / SHOULD** as in RFC 2119.

---

## 0. The governing rule

> iOS MUST NOT publish any 36669 or 30078 event unless it has, in the same session, fetched the user's current relay copy of that address **and decrypted it**, or every relay in the user's write set has answered (EOSE) with nothing, and merged against the result.
>
> A timeout, an unreachable write relay, or a decrypt failure is **unknown**, never "empty". Unknown blocks the publish for that address; the outbox retries. If a write relay stays unreachable across retries, iOS asks the user before publishing that address rather than proceeding on its own.

> **Amended (r5, 2026-11-22, Seth event 5c471a7e approving the proposal in event ccbaa657's follow-up): see §0.1. Where §0.1 applies, it replaces "every relay in the user's write set has answered".**

Every other section is an application of this rule. On Nostr, publishing a newer event to an address replaces the old one; there is no server-side merge. A blind publish is a silent overwrite.

### 0.1 Amendment r5: two-relay "no copy" rule and delivery (Seth, 2026-11-22, event 5c471a7e)

Seth's seven safeguards, quoted from event 5c471a7e:
> 1. If any relay returns an existing remote version, evaluate it through our established merge/conflict rules before publishing.
> 2. Relays that time out or fail are unresolved, not treated as empty.
> 3. If fewer than two relays provide valid empty responses, retain the reflection locally and defer publishing without interrupting the user.
> 4. Continue checking unanswered relays after publishing. If a newer remote version appears, preserve both versions and surface the conflict for review. Never silently overwrite either version.
> 5. Publishing retries must reuse the same signed event.
> 6. Mark an entry as synchronized only after two distinct relay acknowledgments.
> 7. Ensure the outbox survives application restarts and delayed retries never replace newer local or remote edits.

How iOS applies them:

**Before publishing a day (the overwrite check):**
1. **A remote copy found anywhere wins attention first.** If any relay, read or write, returns a version of that address, it goes through §4 merge/conflict before anything is published.
2. **"No copy exists" needs 2 distinct configured write relays** to have completed the lookup for that address and returned EOSE with nothing, in the same session.
   - **Fewer than 2 write relays (Seth, Option A, event 3f1c5fd4).** If the user's own list names fewer than 2 write relays, **all** of them are required, for both the lookup and the acknowledgements.
     - With one write relay, one completed empty lookup permits publishing, and one `OK true` marks the entry synchronized.
     - A timeout, auth failure or incomplete lookup is still not empty.
     - Any remote version found still goes through §4.
     - Local entries and the outbox are kept when delivery fails.
     - Default relays are **never** added to a user's explicit list.
   - **No writable relays in the user's list:** nothing is published anywhere. Sync is deferred, and the person gets a clear, nontechnical explanation when appropriate (copy: Prep).
   - Read-only relays never count toward the 2 and never block.
3. **Timeouts, errors and auth-`CLOSED` are unresolved, never empty.**
4. **Fewer than 2 valid empty answers:** keep the reflection local and defer the publish. Retry quietly, with no prompt.
5. **Re-check after publishing.** Every write relay that hadn't answered is re-queried later. If it holds a newer version, both versions are kept and the conflict is surfaced for review (M6). Neither is ever silently overwritten.

5a. **"A version I didn't base on," not "a newer version"** (Audit, r5 review). Each queued event records its base, the remote version the edit started from. Before every send (the first send and every retry), iOS refetches that address. If any version exists that is neither the base nor this device's own event for that day, the queued event is never sent, and the day becomes a conflict with both texts kept, whatever that version's `created_at`. The post-publish re-check (5) uses the same test.
   - **Take-remote rule:** events carry no parent reference, so iOS can't prove descent. iOS takes a remote version over a local row only when the row has **no pending local edits**, and it always **archives the replaced local text first**, in the local "earlier version" archive (§4.4). A row *with* pending edits plus any version it didn't base on is a conflict.
   - **Residual:** a version arriving at a relay during the roughly 1-second send window can still be replaced on relays that keep only the newest event. The other device keeps its text: in its archive if it had no pending edits, otherwise as a conflict. Only web can overwrite silently (§4.4).

**Delivery:**

6. **Retries reuse the same signed event** (same `id`, `created_at`, `sig`). A delivery failure never re-signs. A newer local edit supersedes older queued events for that address, and superseded events are never sent again.
7. **Acknowledgements:**
   - An address counts as synchronized only after **2 distinct relays** return `OK true` for that event id. If the user's list has one write relay, that one relay's `OK true` is enough (Option A). A `duplicate:` `OK true` counts.
   - The outbox and acknowledgement sets persist across restarts.
   - A delayed retry can't replace a newer edit, because relays keep the newest `created_at` and superseded events are never resent.

What doesn't change: event formats, encryption, and §4's rules.

---

## 1. Kind 36669 — Daily entry

### 1.1 Shape (what web writes; iOS MUST write the same)

Built in `src/components/DayDetailDialog.tsx:460-505`.

| Field | Value | Ref |
|---|---|---|
| `kind` | `36669` (addressable) | |
| `created_at` | now, unix seconds | `src/hooks/useNostrPublish.ts:57` |
| tag `d` | `YYYY-MM-DD`, the **device-local** calendar date | `:473`, `src/lib/gratitudeUtils.ts:55-60` |
| tag `published_at` | unix seconds of **local midnight** of that date (not save time) | `:470-474` |
| tag `day` | local day-of-year 1–366 | `:475` |
| tag `alt` (public) | `Daily reflection entry for <Weekday, Month D> (Day N)` (en-US date, no year) | `:483` |
| tag `encrypted` (private only) | `["encrypted","nip44"]` | `src/lib/privacyUtils.ts:15` |
| tag `alt` (private) | `Encrypted gratitude journal entry` | `privacyUtils.ts:18` |
| tag `client` | web adds hostname; iOS MAY add `["client","Grateful Day iOS"]` | `useNostrPublish.ts:49-51` |

Tag order on web: `d`, `published_at`, `day`, then `encrypted` (if private), then `alt`. Order has no semantic meaning but iOS SHOULD match it so fixtures compare byte-for-byte before signing.

**No other tags.** No `p`, `t`, `title`, `e`. Mentions in text stay as `nostr:npub…` without p-tags.

### 1.2 Content

- **Plain text, never JSON.** One day can hold several notes. Canonical form: each note trimmed, empties dropped, joined with exactly `\n\n` (`src/lib/entryNotes.ts:13,38-43`).
- **Reading:** normalize `\r\n` and lone `\r` to `\n`, split on one or more blank lines (whitespace-only lines count as blank), trim, drop empties (`entryNotes.ts:16,25-31`). Single newlines stay inside a note.
- iOS MUST normalize with this exact algorithm before encrypting or publishing, and MUST NOT publish empty content (web blocks it).
- No max length on web, but NIP-44 v2 caps plaintext at **65,535 bytes**, so web's private save fails above that. iOS MUST cap a day's canonical content at 65,535 UTF-8 bytes (public and private alike, so toggling privacy can't make an entry unpublishable) and block the save with a clear message rather than truncate.

### 1.3 Private entries (encryption)

- Content = NIP-44 **v2** payload of the canonical plain text, conversation key derived from (own privkey, own pubkey) — i.e. encrypted to self. Web delegates to the signer (`privacyUtils.ts:57-75`); iOS uses `NostrCore`'s NIP-44 with the official test vectors passing.
- An entry is private **iff** it has a tag `encrypted` with value `nip44` (`privacyUtils.ts:29`). iOS MUST NOT infer privacy from content shape.
- Encryption failure MUST fail closed: never fall back to publishing plaintext (web: `DayDetailDialog.tsx:131,145`).
- Decryption failure on read: show the entry as "can't be opened on this device", never as empty, and never offer an edit that would replace it.
- **Visible on private entries (Option A, disclose to the user):** author pubkey, `d` date, `day`, `published_at`, `created_at` (= save time; every edit republishes, so edit times too), approximate length (NIP-44 pads, but buckets still leak size).

### 1.4 Validation on read

iOS MUST accept an event as an entry only if all hold:
- kind 36669, `pubkey` == the signed-in user, signature valid, id matches.
- `d` matches `^\d{4}-\d{2}-\d{2}$` and is a real calendar date.
- `day` integer 1–366; `published_at` integer > 0 (web: `src/hooks/useGratitudeEntries.ts:172-196`).

Signature and author checks are iOS additions; web does not need them because it filters by `authors` at the relay, but iOS MUST NOT trust relays.

### 1.5 Replacement (which version is current)

- Per `d`, the event with the highest `created_at` wins (web: `src/lib/streakUtils.ts:34-48`).
- **Tie on `created_at`:** web keeps the first one seen (strict `>`), which is non-deterministic across relays; this is a known web difference from NIP-01. iOS MUST break ties by the lexically lowest event `id` (NIP-01 rule).
- **Clock skew:** iOS MUST publish with `created_at = max(now, remote.created_at + 1)`, where `remote` is the newest version fetched under §0. A device clock running behind would otherwise produce an older event that relays silently discard.
- Fetch MUST query the union of the user's read **and** write relays (own events live on the write relays) and dedupe across them.
- **Paging:** web fetches own entries with `limit: 500` and no paging (`useGratitudeEntries.ts:23-34`). Because relays replace each day's entry, that caps **days**: a user with more than ~500 journaled days already loses their oldest days on web (pre-existing web issue). iOS MUST page by `until` until a page returns no new events, so a full sync is complete.

### 1.6 Writing and editing

- An edit republishes the **whole day** (all notes) with the same `d` and `created_at = now`.
- **Privacy on edit:** web defaults the toggle to the existing event's state (`DayDetailDialog.tsx:346-348`) but lets the user flip it. iOS SHOULD do the same.
- **Public → private is not a takeback.** Relays that don't replace addressable events, and any client that already fetched it, keep the old plaintext. iOS MUST tell the user this when they make a previously public entry private. (Flag for Audit and Prep; web has the same gap and says nothing.)
- Before publishing an edit, iOS MUST run the §4 conflict check against a fresh fetch of that `d`.

### 1.7 Deletion

Web (`src/hooks/useDeleteGratitudeEntry.ts:34-43`, `src/lib/entryTombstones.ts`):
- Publishes kind 5, content `Deleted gratitude entry`, tags `["a","36669:<pubkey>:<d>"]`, `["e",<event id>]`, `["k","36669"]`.
- Records a local tombstone (`gratefulday:deleted-entries:v1`, coord → deletion `created_at`) and hides versions with `created_at ≤` that time. A newer re-created entry for the same day stays visible.
- **Web never reads kind 5 events back.**

iOS requirements:
- MUST publish the identical kind 5 shape.
- MUST read the user's own kind 5 events with `#k: ["36669"]` (and `authors:[self]`) and apply them with the same `created_at ≤ deletion` rule, so deletes made on web hide on iOS even when relays ignore them.
- MUST keep its own durable tombstones (same semantics) for deletes made offline, and queue the kind 5 in the outbox.

**Known gap (needs approval to fix):** a delete made on iOS keeps showing on web until every relay drops the event, because web relies only on its local tombstone. Fix = web reads own kind 5 events (small change in `useGratitudeEntries.ts`). This is a web repo change and is not authorized yet.

### 1.8 Dates and time zones

- `d` and `day` are the device's local date at the moment of writing; `published_at` is that date's local midnight. There is no UTC anywhere (`gratitudeUtils.ts:23-27,46-60`).
- iOS MUST compute them the same way from `Calendar.current` and `TimeZone.current`.
- iOS MUST treat `d` as the identity of the day and MUST NOT recompute `d` from `published_at` (they disagree across time zones).
- Consequence (accepted for MVP, Prep to confirm): travelling users may skip or double a calendar day; streaks follow `d`.

---

## 2. Kind 30078 — Encrypted settings

### 2.1 Shape

`src/lib/appSettings.ts:22-27,165-175`.
- `kind 30078`, tags exactly `["d","gratefulday:settings"]`, `["encrypted","nip44"]`, `["alt","Encrypted gratefulday settings"]`.
- Content = NIP-44 v2 self-encrypted JSON:

```json
{"version":1,"privacyDefault":true,"celebratedMilestones":[7,30],"lastSeenNotifications":1795280000}
```

- `privacyDefault`: boolean or absent. `celebratedMilestones`: sorted unique numbers, never contains `1`. `lastSeenNotifications`: unix seconds or absent. (`appSettings.ts:30-40,108-128`)

### 2.2 Reading

- Query `{kinds:[30078], authors:[self], "#d":["gratefulday:settings"], limit:20}`, take the highest `created_at` (`src/hooks/useAppSettings.ts:84-93`, `appSettings.ts:130-136`).
- Parse tolerantly: wrong types become absent/empty; undecryptable reads as "no remote settings" (`appSettings.ts:108-128,148-163`).

### 2.3 Merge rules (iOS MUST implement exactly)

From `reconcile` (`appSettings.ts:52-84`) and `updateSettings` (`useAppSettings.ts:126-150`):

| Field | Rule |
|---|---|
| `privacyDefault` | Last write wins: remote value if remote has one, else local. A local change overwrites. |
| `celebratedMilestones` | **Union** of local and remote, sorted. Never remove a milestone. |
| `lastSeenNotifications` | **Max** of local and remote. Never move backwards. |

### 2.4 Writing

- Every write publishes the full merged object with `created_at = now`.
- **iOS MUST NOT publish settings unless the remote fetch in §2.2 succeeded in this session** (or every write relay confirmed none exists). Reason: if iOS publishes from local state alone, the newer event drops milestones another device recorded, and web's next `reconcile` will see the smaller set as "remote".
  - **A failed decrypt is not "no settings".** Web's `decryptSettings` returns null on failure (`appSettings.ts:148-163`) and then treats it like a missing event. iOS MUST treat it as unknown and not publish.
  - **Decrypted text that isn't a valid JSON object is not "no settings" either (MUST, Seth 2026-11-21).** iOS MUST treat it as unknown and block the write, exactly like a failed decrypt. This MUST be met before iOS gets any settings write path. Phase 0's `AppSettings.parse` stays tolerant to match web and returns empty settings for that case, so a writer must never use that result as the base it publishes over. Web has the same gap (`parseSettings` → `emptySettings()`); fixing it there is a separate follow-up that needs Seth's approval (tracked by Chief). Principle: never silently overwrite user data when the remote state can't be reliably read or interpreted. [source: buzz://message?channel=9a37a94b-4f0e-4237-bbc7-c1fe3a4ee887&id=3d4647db29c60b8f34b7892e45a74ef0a674445ac248ec33ba1c04fa38f59905]
- Web itself does not follow this rule: `updateSettings` publishes even when the remote query failed or timed out (3 s), and the seed path (`useAppSettings.ts:155-173`) runs when the query produced nothing, including after a timeout or decrypt failure. Fixing that is a web change and needs approval. That is a pre-existing web risk to note for Audit; milestones survive only because each device unions its own local cache back in.
- **Seeding:** if no remote event exists and local has anything worth keeping, publish once (web: `needsSeed`, `appSettings.ts:89-96`; `useAppSettings.ts:155-173`).
- **iOS MUST round-trip `lastSeenNotifications`** even though the iOS MVP has no notifications. Dropping it would make web re-show read notifications.
- **iOS MUST NOT add fields to this event.** Web's `serializeSettings` writes only the three known fields and `parseSettings` discards anything else (`appSettings.ts:98-128`), so any iOS-only field is deleted the next time web saves. iOS-only settings go either local or in a separate 30078 with a different `d` (e.g. `gratefulday:ios-settings`) — Prep/Audit to decide if any are needed.
- **Version:** iOS writes `version: 1`. If iOS ever reads `version > 1`, it MUST NOT write the settings event (read-only) until updated.

### 2.5 Scope of sync (Seth: nonessential data can stay local)

- Syncs: entries (36669), privacy default, milestones, notification read state (30078).
- Stays on device on both clients: wisdom history (`gratefulday:wisdom:v1:<pubkey>`, documented in `docs/DAILY_WISDOM.md`), local tombstones, mutes/hidden notes (social, out of MVP).

### 2.6 Milestones: web and iOS mean different things (Prep, 2026-11-22, Chief P36 event 0b59784a)
**Web's `celebratedMilestones` are consecutive-day streak milestones.** Verified in `~/.buzz/REPOS/gratefulday` @ `a33f42c`:
- `pickCelebration` (`src/lib/streakUtils.ts:144-150`) checks `getReachedMilestones(current)`, and `current` is the current consecutive-day streak (`CelebrationInput.current`, `:124-125`).
- `MilestoneCelebrationDialog.tsx:96-101` stores `MILESTONES.filter(m => m > 1 && m <= next)`, with `next` picked from the streak.
- The copy says so: 14 is "Fourteen days in a row", 30 is "Thirty consecutive days", 200 is "Two hundred days without missing one" (`:18-55`).
- `1` is the only total-based one: it comes from `total === 1` and is never stored (`streakUtils.ts:128-143`).

**iOS milestones are totals** (Phase 1 scope item 7: 1st, 7th, 30th, 100th, 365th reflection). The same number means a different thing on each client, so a union would tell web that streaks were celebrated when they weren't.

**Product rulings:**
1. **iOS never writes iOS milestones into `celebratedMilestones`.** Not now, and not later, while web's are streaks. Reconsider only if web moves to totals, which would be a web change needing Seth.
2. **iOS doesn't read `celebratedMilestones` to decide its own acknowledgements.** It round-trips them untouched, under §2.4, if it ever writes this event.
3. **iOS acknowledgements stay on this iPhone, recorded per account.** No `gratefulday:ios-settings` event; §2.5 already lets nonessential data stay local. On a new iPhone or after restore, milestones the account had already passed when it connected are marked seen without being shown. Only crossing a total on this iPhone shows the line. That keeps "shown once" in practice and never greets someone with a backlog.
4. **So iOS has nothing of its own to write to 30078 in the MVP.** It has no privacy default (private by default, §1.3), no notifications, and no milestones to merge. P36's "settings writes" follow-up is **closed, not pending**. Reopen it only if an approved iOS feature needs a setting that web also reads (for example, a privacy default). Reading stays as P36 set it.

---

## 3. Local-first model on iOS

- **Store is the source of truth.** One record per `d`: canonical notes text, `isPrivate`, `localModifiedAt`, `syncState` (`localOnly` / `pending` / `synced` / `conflict` / `deleted`), `baseEventId` + `baseCreatedAt` (the remote version this edit started from), and the last raw remote event for that `d`.
- **No account:** records stay `localOnly`. Nothing is signed or encrypted with a Nostr key; the store relies on iOS file protection (`NSFileProtectionComplete`). Privacy choice per entry is still recorded so it applies when published.
- **Outbox:** signed events wait in a durable queue; retried with backoff on connectivity change and app foreground. Before sending, each queued 36669/30078 is re-checked under §0 and §4 — a queued event is re-signed with a fresh `created_at` if it went stale, never sent with an old one.
- **Publish success:** at least one write relay returns `OK true` (web: any one relay). iOS SHOULD keep retrying the remaining write relays in the background.

---

## 4. Conflict detection and resolution

A **conflict** exists for a `d` when iOS has local changes and the newest remote version is not the one the local edit started from (`remote.id != baseEventId`), or a remote version exists and the local record has never seen one (first connect).

### 4.1 First connect (local journal → Nostr account)

0. **Before anything is published**, show the disclosure Seth asked for (Prep owns wording). Linking is the user's first publish and may publish the whole local journal at once.
1. Full fetch of the user's 36669 (paged, §1.5), 30078 and own kind 5 (§1.7). A date counts as checked only when every write relay has answered for it (§0). Dates that aren't checked yet stay `localOnly` and are retried; they are never published on a partial fetch.
2. For each local `d`:
   - No remote version → publish (private per the record's choice) with `created_at = now`.
   - Remote version deleted (kind 5 covers it) and local has text → treat as new; publish.
   - Remote exists, decrypted text equals local canonical text → mark `synced`, no publish.
   - Remote exists and differs → **conflict**. Do not publish.
   - Remote exists and cannot be decrypted → **blocked**. Never treat as empty, never publish over it; keep local and tell the user.
3. Settings: merge per §2.3, then publish once.
4. Remote days with no local record → import as `synced`.

### 4.2 Ongoing sync

- Remote newer than base, no local edits → take remote.
- Local edits, remote unchanged since base → publish (after the §1.6 fresh fetch).
- Both changed → conflict.
- **Remote delete vs. unsent local edit:** a kind 5 (or local tombstone from web arriving via kind 5) covering a `d` for which iOS holds unpublished edits is a **conflict**. iOS keeps the local text, does not publish, and asks the user whether to restore the day or accept the delete. It MUST NOT silently undo the delete or silently drop the edit.
- These rules, including §0's "every write relay answered" condition, apply to every ordinary edit in Phase 2, not only to first connect.

### 4.3 Resolving a conflict (product: Prep owns the UI)

Technical options, all of which preserve writing:
- **Combine (recommended default):** union of notes from both versions — `splitNotes(remote) + notes in local not already present` — keeps everything, then publish. Works because notes are blank-line separated plain text. Dedup is exact-match only, so a note edited on one side appears twice (old and new); nothing is lost, but the conflict screen should let the user remove the duplicate before publishing (Prep).
- Keep mine / keep theirs: the losing side is kept in a local "earlier version" archive, never discarded.
- If one side is private and the other public, the result MUST default to **private** and ask before publishing anything public.
- A remote version that cannot be decrypted MUST NOT be overwritten automatically.

### 4.4 What iOS cannot prevent (residual risk, for Audit)

- **Web overwrites iOS.** (gratefulday's `AGENTS.md:301` says the default pool reads from one relay, but that is generic template text: at `a33f42c` `src/components/NostrProvider.tsx:31-43` routes reads to all read relays. The risk comes from the timeouts, not a single-relay read.) Web edits the day it loaded; if it loaded before an iOS publish arrived (web query timeouts are 1.5–3 s, `useGratitudeEntries.ts:23-69`), web's save replaces the iOS version with no warning. iOS will see the newer web event and, if iOS has no pending local edits, simply accept it. iOS keeps the replaced version in its local archive so nothing written on iPhone is lost on the iPhone, but web gives no such protection. Fixing this needs a web change (base-version check before save).
- **Slow relay on web can hide an existing entry**, so a web user writes "fresh" over it. Pre-existing web behavior.

---

## 5. Relays

- Read/write set: the user's NIP-65 kind 10002 list when it exists (web: `src/components/NostrSync.tsx:21-49`; an `r` tag without marker = read+write).
- Defaults when none: to be proposed separately and reviewed by Audit. Web's defaults (`src/App.tsx:38-46`: damus, nostr.band, nos.lol, primal, nostr.wine) are a starting point, not a requirement; interop only needs overlap with where the user's web client reads and writes, which NIP-65 provides.
- iOS MUST NOT publish a kind 10002 in MVP (it would replace the user's list on every other client).

---

## 6. Test fixtures required before implementation

- NIP-44 v2 official vectors (conversation key, encrypt/decrypt, padding) passing in `NostrCore`.
- Real events captured from the web app at `a33f42c` on a test key: public entry, private entry, multi-note entry, CRLF content, edited entry, kind 5 delete, settings event (incl. `lastSeenNotifications`). iOS decodes each, and web decodes iOS output for the same inputs.
- Merge tests for §2.3 and every branch of §4.1/§4.2.
- Time zone tests: same instant in UTC−10 and UTC+14 produce the expected `d`, `day`, `published_at`.

---

## 7. NIP.md drift (for whoever later updates web docs)

NIP.md at `a33f42c` says `published_at` is creation time (code: local midnight), shows an alt format the code no longer writes, and omits: the `encrypted` tag, the encrypted alt, multi-note content, kind 5 deletion, and the 30078 settings event. This spec describes the wire; NIP.md should be updated to match once the web repo change is approved.

---

## 8. Open items

| # | Item | Owner |
|---|---|---|
| 1 | Approve web change: read own kind 5 deletes (§1.7) | Seth / Prep |
| 2 | Approve web change: base-version check before save (§4.4) | Seth / Prep |
| 3 | Conflict UI and "combine" as default (§4.3) | Prep |
| 4 | Public→private disclosure wording (§1.6) | Prep, Growth, Audit |
| 5 | Validate this spec against web behavior; residual risks §2.4, §4.4 | Audit |
| 6 | Whether any iOS-only synced settings are needed (§2.4) | Prep |
| 7 | Default relay list (§5) | Sous proposes, Audit reviews |

---

## 9. Revision log

- r5.2 (2026-11-22): §2.6 added (Prep, Chief P36): web milestones are streaks and iOS milestones are totals, so they're never merged. iOS acknowledgements stay local per account, and iOS writes no 30078 in the MVP.
- r5.1 (2026-11-22): surfacing rule for archived self-published text with lost notes (Chief P22). Option A for fewer than 2 write relays, and the no-writable-relay case (Seth, event 3f1c5fd4); item 5a ("a version I didn't base on"); the take-remote rule (no pending edits plus archive first).
- r5 (2026-11-22): §0.1 amendment approved by Seth (event 5c471a7e): "no copy" needs 2 distinct write relays' empty answers instead of all; unanswered relays re-checked after publish (conflict, never overwrite); retries reuse the same signed event; synchronized = 2 distinct acknowledgements; persistent outbox.

- r4 (2026-11-21): §2.4 adds the MUST that non-JSON decrypted settings are unknown and block writes (Seth).

- r2 (2026-11-21): incorporates Audit's validation (buzz://message?channel=9a37a94b-4f0e-4237-bbc7-c1fe3a4ee887&id=35ca9c747a1e24edb6d69ed7ac5c4fd8b67aee6b84ad43ada49f03fa078956ce): §0 unknown ≠ empty and all write relays must answer; §1.2 65,535-byte cap; §2.4 decrypt failure ≠ no settings, web seed path noted; §4.1 disclosure before first publish, undecryptable remote blocks the date; §4.2 rules apply to every edit; §1.5 web tie-break noted as differing from NIP-01.
- r3 (2026-11-21): Audit re-validation PASS conditional on two MUSTs, both applied (buzz://message?channel=9a37a94b-4f0e-4237-bbc7-c1fe3a4ee887&id=29daaa1ffd901c8bd81d811b18e7842a986a756182a74d007afe2fb4ae39488a): §4.2 remote delete vs unsent local edit = conflict; §1.5 `created_at = max(now, remote.created_at + 1)`. Minor: fetch read ∪ write relays; 500 limit caps days; combine duplicates note for Prep; Audit's single-relay point checked: AGENTS.md says so, code reads all read relays (§4.4). Ready to lock pending Seth's go.
- Follow-up outside this spec: KeyStore design (import incl. clipboard handling, export/backup, Keychain wipe on account removal, no-logging) is required by Audit before Phase 2 code.

## Addendum (Sous, 2026-11-21): settings codec must keep unknown keys
From Audit's PR #42 review (Info, existed before that PR). Web `serializeSettings` writes back only the three fields it knows. So a field added by a newer client is dropped the next time the web app saves. The iOS settings codec must keep unknown JSON keys when it rewrites (read, merge, write back the whole object). Check this in M5. [source: buzz://message?channel=9a37a94b-4f0e-4237-bbc7-c1fe3a4ee887&id=d918e614f431cacb8027f1fc8a1eba73f8194d39f66864b8c225151474963f17]
