---
title: "Grateful Day iOS — M5 Account Flows and Warning Copy (Prep)"
tags: [grateful-day, ios, m5, product, copy, keys]
status: active
created: 2026-11-21
---

Source: Seth's M5 decisions, #general event 43dbe869 (2026-11-21). Built on the key design r2 (PLANS/GRATEFUL_DAY_IOS_KEY_STORAGE_BACKUP_DESIGN_2026_11_21.md, §5–§8) and MVP specs A and B.
Where this doc and the design doc disagree on **user-facing behaviour or copy**, this doc wins. Mechanism, Keychain classes and ordering belong to Sous and Audit.
Copy below is final for in-app use. Growth may tune wording only if every fact stays. Guarantee wording stays off until the device checks pass (Seth §6).

## Terms
- **"Journal key"** is the user-facing term (confirmed). Never "secret key", "private key" or "nsec", with one exception: the "Use my Nostr account" import screen (F5), which only people who already have a Nostr key reach.
- **"Your account"** means the reflections saved to Nostr. **"iCloud Keychain"** means only the journal key backup. No copy may suggest iCloud holds reflections.

## What changed from the design doc (Seth's sign-out decision)
- **Sign out** removes the journal key from this iPhone and **keeps the journal**. Reflections stay readable and writable.
- **Remove account and local data** is a separate, explicit, destructive action.
- **Account isolation after sign-out (Chief P16/P17, which supersede Prep's earlier "block B" rule):** each entry belongs to an account (or none, for guest). Signed out counts as guest. Another account (B) can connect, and A's entries are never edited, published or merged under B. How A's days look is in "Days from another account" below.

---

## F1 — Connect entry point
Reached from Settings → Account, or from the connect prompt (after the 3rd saved reflection, per the MVP).
Heading: **"Keep your reflections safe"**
Options, in this order:
1. **"I've used Grateful Day before"** → F3
2. **"Create a journal key"** → F4, then F2
3. **"Use my Nostr account"** → F5
Footer: [Not now]. Nothing is published, and nothing changes.

## F2 — Back up the journal key (right after a key is created)
A clear yes-or-no choice. Nothing is preselected, and the backup is never turned on automatically.
- Heading: **"Keep a backup of your journal key?"**
- Body: "Your journal key opens your private reflections. If this iPhone is lost and there's no backup, they can't be opened again, even though they're saved to your account. We can keep a copy of your journal key in iCloud Keychain. Anyone who can sign in to your Apple account on a trusted device could restore it."
- Buttons: **[Back up to iCloud Keychain]** · [Don't back up]

**After backing up:** "Journal key backup saved. It reaches your other devices if iCloud Keychain is on (Settings → your name → iCloud → Passwords & Keychain)." (Never "backed up" alone, since the app can't verify sync. And "journal key", so nobody reads it as their reflections.)

**If they choose Don't back up**, one confirmation:
- "Without a backup, losing this iPhone means your private reflections can't be opened again."
- [Go back] · [Continue without backup]

**Later:** Settings → Account → "Back up journal key" is always available while no backup exists on this iPhone.

Then the spec A disclosure sheet (if not yet accepted), fetch first, publish. A brand-new key has nothing remote, so there's no conflict screen.

## F3 — "I've used Grateful Day before" (restore)
- **Searching:** "Looking for your journal key backup…"
- **Found one:** "We found your journal key backup." [Restore]. Then the spec A sheet if needed, fetch-first connect, and the spec B conflict review.
- **Found several:** list them by creation date ("Backup from November 21, 2026"), newest first. Nothing is overwritten.
- **None found yet:** "Your backup hasn't arrived from iCloud yet. Make sure iCloud Keychain is on in Settings, then try again. If you never made a backup, your old journal key can't be restored here." [Try again] · [Use my Nostr account] · [Back]
  - **No "create a key" button on this screen (Seth §3).** Starting fresh means going Back to F1 and through the F4 confirmation.
  - The app checks again on later launches. While it's waiting, Today shows one quiet line: "Still looking for your journal key backup." Tapping it reopens F3. It goes away when the backup is found or the person dismisses it.

## F4 — Create a journal key (always confirmed)
- Heading: **"Make a new journal key?"**
- Body: "If you've used Grateful Day before, reflections saved with your old journal key won't open with a new one."
- Buttons: **[Make a new key]** · [I've used it before] (goes to F3)
- Shown to everyone, every time. It reads fine for a first-time user, and one rule is simpler and safer than guessing who's new.

## F5 — Use my Nostr account
- Uses whatever import or signer mechanism Sous's M5 design specifies and Audit passes (Seth §3). No new mechanism without Seth.
- Import screen copy: "Paste your Nostr secret key (nsec). It stays on this iPhone and is never sent anywhere." (This is the one place "nsec" may appear.)
- Then the F2 backup offer, the spec A sheet, fetch-first connect and the spec B review.
- Import while signed out with A-owned days on the phone is allowed (P16). A's days stay read-only as described in "Days from another account".

## F6 — Key problems (from design §7)
None of these offer to create a key. In all of them, writing on this iPhone keeps working.
- **Key missing** (marker present, no key): "Your journal key isn't on this iPhone. Restore it from your backup to keep saving to your account. Your reflections on this iPhone are still here." [Restore] → F3
- **Mismatch:** "This iPhone has a different journal key from the one your journal uses. Nothing will be saved to your account until this is sorted out. Your reflections on this iPhone are still here." (No automatic fix in MVP.)
- **Unknown / Locked / Key unavailable:** no new screen. Days show the existing "Not backed up yet" mark, and the M2 locked/failed states apply. No account or onboarding prompts while the state is unknown.

## F7 — Sign out (keeps the journal)
Settings → Account → **Sign out**. One sheet, built from parts:
- Heading: **"Sign out on this iPhone?"**
- Always: "Your journal key will be removed from this iPhone. Your reflections stay here, and you can keep writing."
- If any reflection is unsynced, **or the sync state can't be read** (then count all local reflections): "**N reflections** haven't been saved to your account yet. They'll stay on this iPhone and be saved when you sign back in with the same account."
- If **no backup** is found on this iPhone: "There's no backup of your journal key. Without it, you can't sign back in, and your private reflections can't be opened on any other device."
- Buttons:
  - With a backup: [Cancel] · **[Sign out]**
  - Without a backup: **[Back up first]** (→ F2) · [Sign out anyway] · [Cancel]

**After signing out:** entries show "On this iPhone only" again, and the pre-account statement applies. Signing back in follows the isolation rule above.
**If removing the key fails:** "Couldn't sign out just now. Nothing has changed." (Audit verifies ordering: the key delete is confirmed before the account state changes.)

## F8 — Remove account and local data (destructive)
Settings → Account, at the bottom, styled as destructive.
**Step 1:**
- Heading: **"Remove account and local data?"**
- "This removes your journal key and every reflection from this iPhone. Reflections already saved to your account stay there."
- If unsynced (or the sync state can't be read): "**N reflections** are only on this iPhone and will be permanently deleted."
- If no backup: "There's no backup of your journal key, so the reflections saved to your account can't be opened again."
- [Cancel] · **[Remove]**

**Step 2:** a second confirmation, with the count when there is one: "Permanently delete N reflections from this iPhone?" (or "Remove everything from this iPhone?" when none are unsynced). [Cancel] · **[Delete]**

**Step 3, only if a backup exists:** "Also delete the iCloud backup of your journal key?" "If you delete it, you can't restore this journal key later, and reflections saved to your account can only be opened with it." **[Keep backup]** (default) · [Delete backup]

**Failures:**
- Nothing done yet: "Couldn't remove everything just now. Nothing has been deleted."
- Key removed but local data not yet cleared: "Your journal key was removed, but the reflections on this iPhone couldn't be deleted yet." [Try again]. The ordering, and whether this state can happen, is Audit's to verify.

---

## Acceptance (product side; Audit owns security and ordering)
1. No path creates a key without the F4 confirmation. F3 and F6 never offer creation.
2. The backup is never on without a tap on [Back up to iCloud Keychain]. Declining takes one extra confirmation and loses nothing.
3. No surface says or implies that iCloud holds reflections, that a backup is verified, or that anything is "secure" or "safe" beyond the approved sentences.
4. Sign out never deletes a reflection. Only F8 does, and only after two confirmations that show the count of unsynced reflections, counting all of them when the sync state is unknown.
5. After sign-out, another account may connect (P17). A's entries are never edited, published or merged under it. The same account reconnects through fetch-first and the spec B review.
6. Every warning that mentions unsynced reflections or a missing backup shows only when it's true for this iPhone.
7. "nsec" appears only on the F5 import screen.
8. Each failure message states what happened to the user's data ("Nothing has changed" / "Nothing has been deleted") and is true in that state.

## Fit with Chief's P13–P15 (event 7a5c8e63)
- **P13:** F1–F8 all ship in M5a, except the fetch-first and publish steps after F2/F3/F5, which arrive in M5b. In M5a, connecting stops after the key is stored and backed up. Days stay "On this iPhone only" until M5b.
- **P14:** import only, no NIP-46 signer. F5's copy covers it. The earlier open question is closed.
- **P15/P16/P17:** Prep's earlier "block B until remove-all" rule is withdrawn in favour of Chief's P17 (option a). Display rules are in "Days from another account".

## Days from another account (Prep, 2026-11-21, Chief P17 event 9e840c7d)
Applies whenever this iPhone holds rows owned by an account that isn't the current one: signed out after A, or connected as B. "Current journal" means guest rows plus the connected account's rows.

**Label:** "From another account". It's true in both cases, and doesn't name or guess who. Tapping it shows: "This reflection was written while signed in to a different account. It stays on this iPhone, read-only, and isn't saved to the account you're using now." The label never shows the other account's npub or name.

**Calendar**
- A day with only another account's reflection gets its own mark: an outlined dot, not a filled one, so it doesn't rely on colour. VoiceOver says "Reflection from another account".
- Opening it shows the text read-only, with the label at the top. No edit or delete controls.
- A day with both: the current journal's reflection shows first, normally. Below it is a collapsed "From another account" section that opens read-only.

**Today**
- If today has another account's reflection, Today still opens the current journal's editor, empty if needed. One quiet line above it: "You also wrote today under another account." Tapping it opens that reflection read-only.
- Never pre-fill the editor with the other account's text.

**Counts, milestones, Welcome back: the current journal only**
- "N reflections this month", totals and milestones count only the current journal. Another account's days never count and never trigger a milestone.
- **Why:** counts mean "your reflections in the journal you're using now". Mixing owners would double-count when A reconnects and could fire milestones for B from A's writing.
- **No reset feeling:** when another account's days exist, the Calendar shows one quiet line under the counts: "N earlier reflections from another account are kept on this iPhone." Nothing is hidden. It just isn't counted.
- Welcome back looks only at the current journal.

**Lifecycle**
- When A reconnects, A's days become the current journal again: normal marks, counted, editable per the usual today-only rule. Guest rows written while signed out follow spec B into A.
- "Remove account and local data" (F8) removes **every** reflection on this iPhone, including other accounts' days. F8 step 1 adds a line when they exist: "This includes N reflections from another account."
- Sign out never deletes them. Individual delete isn't offered for another account's days in MVP.

**Acceptance**
1. Another account's reflection is never editable, publishable or deletable on its own while that account isn't connected.
2. It never counts toward counts, totals, milestones or Welcome back.
3. Every place it appears carries "From another account", and VoiceOver announces it.
4. Today never pre-fills from another account's text.
5. F8 counts and removes another account's days and says so.

## Incomplete sync: user experience (Prep, 2026-11-22, Seth event ccbaa657)
**Principle:** writing never waits, and a relay outage is never the user's problem to solve. The user sees two states, not a relay count.

| What the app knows | What the user sees |
|---|---|
| Saved locally, ≥2 write relays acknowledged | **Saved to your account.** No mark; this is the normal, quiet state. |
| Saved locally, 0–1 acknowledgments (offline, outage, retrying) | **Saving to your account.** A small mark on that day, on Today and in the Calendar |
| Guest, no account | "On this iPhone only" (unchanged) |

- **The mark:** one small symbol, not colour alone, with no number and no relay names. VoiceOver says "Not saved to your account yet". Tapping it shows: "This reflection hasn't finished saving to your account. It's kept on this iPhone, and we'll keep trying." No buttons. It replaces the earlier "Not backed up yet" mark and copy everywhere.
- **No prompts, alerts or banners** for normal outages or offline use. No "you're offline" banner. **This drops the design's §0 prompt** ("ask before publishing past a write relay that hasn't answered"): under Seth's decision, publishing never depends on every write relay, so there's nothing to ask.
- **Long-running:** if any reflection has stayed in "Saving" for 7+ days, Settings → Account shows one quiet line: "N reflections haven't finished saving to your account yet. We'll keep trying." [Try now]. Still no alert or badge.
- **One definition everywhere:** "saved to your account" means ≥2 acknowledgments. The sign-out and remove-all warnings ("haven't been saved to your account yet") count everything below that, plus anything whose state can't be read.
- **Connect-time fetch failure (spec B):** change "Your reflections are safe on this iPhone." to **"We couldn't reach your journal yet. Your reflections are still on this iPhone."** This follows Seth's no-unverified-guarantees rule.
- **1 acknowledgment:** the reflection may already show on web, but it still displays as "Saving" until a second relay confirms. That's conservative and never over-claims.
- **Retries** reuse the same signed event, so there are no duplicates. Ack tracking is mechanism (Sous/Audit). Product only needs the two states above.

- **Which days get the mark (Prep, 2026-11-22, #17 product pass):** only days the app is actually trying to send. "We'll keep trying" must be true.
  - **Before spec A is accepted for this account** (including after Not now): unsaved days show "On this iPhone only", not Saving. Nothing is being tried until Continue.
  - **A day too long to save (§8):** the §8 line instead, with no mark and no Calendar symbol.
  - **A day waiting on a choice (§2, §7, §9) or blocked (§5):** its day-view line instead of the mark.
  - **The 7-day Settings line** counts only days that get the mark.
  - The sign-out and remove-all warnings still count every day that isn't saved (acceptance 5).

**Fit with Chief's P21 (event 0bf5878f) and Audit's §0 proposal**
- **The three internal states map to two user states.** "Only on this iPhone" and "sent, 1 acknowledgment" both show the **Saving** mark. "Synced, 2 or more" shows nothing. Sent-but-unconfirmed needs nothing extra.
- **Why the mark copy changed:** the old tap text, "only on this iPhone until it syncs", is false once one relay has the reflection. The new text is true in both internal states. Prep owned the old copy, so this replaces it.
- **On Audit's §0 proposal** (2 write relays answering "none" counts as no copy; a late newer copy becomes an M6 conflict): product is fine with it, because it removes every user prompt. A conflict found later goes to the normal M6 review screen, never to an overwrite. It's still Seth's decision, as Audit says.

**Acceptance**
1. Saving a reflection never shows a spinner, error or prompt because of the network.
2. A day shows "Saving" until ≥2 write relays have acknowledged its latest version, and then shows nothing.
3. No relay names, counts or technical terms appear anywhere in the UI.
4. No modal or alert is ever shown for sync delay. The only escalation is the Settings line after 7 days.
5. Sign-out and remove-all warnings count every reflection that isn't "Saved to your account".

## Zero write relays and surfaced earlier versions (Prep, 2026-11-22, Chief P22 event ad7275c7; Seth option A event 3f1c5fd4)

### 1. Zero write relays (the account's own list has nowhere to save)
Only people who connected an existing Nostr account with an explicit relay list can hit this, so naming "relay" once, in the fix instruction, is acceptable. Nothing else here is technical.
- **Settings → Account**, shown from connect onward while the state lasts. This isn't the 7-day line, because waiting won't fix it:
  > "Your reflections aren't being saved to your account. Your Nostr account doesn't list anywhere to save them. They're kept on this iPhone. To start saving, add a relay for writing in the app you use to manage your Nostr account."
- **Day mark:** the same "Saving" mark, but the tap text changes, because "we'll keep trying" would be false:
  > "This reflection is kept on this iPhone. It can't be saved to your account until your Nostr account lists somewhere to save it. See Settings → Account."
- No alert, banner or prompt. It's never published anywhere else. When a writable relay appears in the list, it returns to the normal states with no message.

### 2. A surfaced earlier version (P22)
**Where:** one quiet line on **Today** (that's where people are, even when the day is in the past), plus the day's own view and Set aside.
- **Today line**, until tapped or dismissed (×):
  - One: "Your reflection from November 20 was replaced by a version saved elsewhere. Your earlier text is in Set aside."
  - Several: "2 reflections were replaced by versions saved elsewhere. Your earlier text is in Set aside."
  - Tap → Set aside, filtered to those items. Dismissing never deletes anything.
- **On that day's view**, a line under the reflection: "An earlier version of this reflection is in Set aside." Tap → that item.
- **Set aside item:** date, "Replaced by a version saved elsewhere", the full earlier text, and [Copy]. No restore in MVP, since past days are read-only. Never auto-purged.
- **"Saved elsewhere"** on purpose: it covers web and another iPhone without guessing which.
- No modal, badge or tab dot. VoiceOver reads the Today line as one element with a "Dismiss" action.
- **Product position on P22's fallback:** if iOS can't tell a race from an ordinary web edit, surface every archived version this device published. Agreed. A quiet line on an ordinary edit costs far less than a silent loss.

## Key delete not confirmed (Prep, 2026-11-22, #13 L1, Chief event 4c4181709)
Used when the Keychain delete call reported success but the confirming re-read was locked or failed, so the key may or may not be gone. It makes no claim about the key. The claim it does make about reflections is true, because in both flows the journal is touched only *after* the delete is confirmed.
- **Remove account and local data (F8):** "We couldn't confirm that your journal key was removed from this iPhone. Your reflections haven't been deleted." [Try again]
- **Sign out (F7), same split:** "We couldn't confirm that you've been signed out on this iPhone. Your reflections are still here." [Try again]
- The existing lines stay for a delete call that actually failed: "Couldn't remove everything just now. Nothing has been deleted." and "Couldn't sign out just now. Nothing has changed."
- Try again re-runs the delete and the confirmation. It never moves on to clearing the journal until the delete is confirmed.

**Zero write relays:** already final. See "Zero write relays and surfaced earlier versions", §1, above.

## Final copy for #14's DRAFT keys (Prep, 2026-11-22, reviewed at #14 head a8d9424; Chief event 0bdc3761)
| Key | Final copy |
|---|---|
| `AccountCopy.keyRemovalUnconfirmed` | Replace the draft. Use **two** lines: F8 "We couldn't confirm that your journal key was removed from this iPhone. Your reflections haven't been deleted." and F7 "We couldn't confirm that you've been signed out on this iPhone. Your reflections are still here." Both get [Try again]. See "Key delete not confirmed". |
| `AccountCopy.backupsSkipped(n)` | n = 1: "One backup couldn't be read, so it isn't listed. It hasn't been deleted." n > 1: "\(n) backups couldn't be read, so they aren't listed. They haven't been deleted." True because backups are never overwritten or deleted by restore. |
| `SyncDraftCopy.blockedDay` | "We can't open this day's reflection from your account on this iPhone. What you wrote here is kept, but it can't be changed for now." This adapts the MVP-approved undecryptable line. |
| `SyncDraftCopy.earlierVersionKept` | "An earlier version of this reflection is in Set aside." (P22 day-view line.) Tap opens the item. |
| `SyncDraftCopy.alsoChangedElsewhere` | "This reflection was also changed elsewhere. Both versions are kept on this iPhone." Same "elsewhere" wording as P22. No promise about when the review screen arrives. |
| `TodayEditorModel.milestoneText` | Approved as is: "Your first reflection." / "That's N reflections." |
| `ReminderModel.title` / `.body` (Reminder.swift:46–50) | Approved as is: title "Grateful Day", body "A quiet minute of gratitude." The body is the approved tagline in full, so the "full line is draft copy" comment is stale and should be deleted. Never add reflection text to the notification. (Prep, 2026-11-22, M5b-1 thread `00d980c7`) |
| `PrivacyStatement` DRAFT comment (lines 8–9) | Only the comment is stale. The statement is already Prep's final, so delete the "DRAFT" note. |

Not a key, but check it's built: the P22 **Today** line for *past* days ("Your reflection from <date> was replaced by a version saved elsewhere. Your earlier text is in Set aside." and the several-reflections form). #14 shows `earlierVersionKept` only when the surfaced day is today.

## M6 conflict screen (Prep, 2026-11-22, Chief event 856495f7)
For days whose text differs between this iPhone and your account. Spec B §4 still governs: Keep both is the default, a text you don't keep goes to Set aside, and private wins on a combined day. Final copy. Growth may tune wording only if every fact stays.

### 1. Heading
- One day: **"You wrote on November 20 in both places."**
- Several: **"You wrote on 3 days in both places."** (as approved in the MVP doc)
- Line under it, always: "Choose what to keep for each day. Any text you don't keep goes to Set aside on this iPhone."
- The count covers only days with a choice to make. Blocked days (§5) are listed separately and aren't counted.

### 2. Each day's row
- Date as the row title: "Thursday, November 20".
- Two texts, each with its label above it. Your account's text comes first, which is also the order they're combined in.
  - **"Your account"**: the text saved elsewhere.
  - **"This iPhone"**: the text written here.
- Long texts show their first lines and [Show all]. Nothing is cut from what's kept.
- VoiceOver reads the label, then the text ("Your account: …", "This iPhone: …").

### 3. Choices per day
Three options, with **Keep both** selected by default. The line under them changes with the choice:
| Choice | Line under it |
|---|---|
| **Keep both** | "Both texts stay on this day as separate notes, your account's first." |
| **Keep this iPhone's** | "Your account's text goes to Set aside." |
| **Keep your account's** | "This iPhone's text goes to Set aside." |
- **Privacy:** if one text is private and the other isn't, and Keep both is selected, add: "This day will be private, because one of the texts was private." With Keep one, the kept text keeps its own setting. Don't add a prompt.
- **Set aside item** for a text that wasn't kept: date, "You kept the other version of this day.", the full text, [Copy]. Never purged automatically, same as P22 items.
- Bottom of the screen: **[Done]** applies every row's choice. After Done there's no message; the days then show the normal Saving mark until they're saved.
- [Not now] closes the screen. Nothing changes and nothing is published for those days. See "Coming back later" below.

### 4. Keep both for all
- A button above the list: **[Keep both for all]**. It applies Keep both to every row with a choice, then closes the screen. There's no confirmation dialog first, because nothing is removed.
- The line that shows afterwards, on Today, until dismissed (×):
  - One day: "Kept both versions on November 20."
  - Several: "Kept both versions on 3 days."
  - Add this only if a combined day became private: "Days where either version was private are now private."
- Blocked rows (§5) are untouched by it.

### 5. Blocked day with unsynced edits
This is a day where your account's text can't be opened on this iPhone, but there's new writing here. It's listed in its own section below the choices, headed **"Can't compare these yet"**. It has no buttons, and it isn't counted in the heading.
- Under "Your account": "We can't open this day's reflection from your account on this iPhone."
- Under "This iPhone": the local text, as normal.
- Under the row: "What you wrote here is kept on this iPhone. It won't replace the reflection in your account."
- Product rule: nothing is published for this day, and no choice is offered, since you can't choose between texts you can't see. It stays like this until the account's text can be opened, and then it becomes a normal row.
- If the only rows are blocked ones, don't open the screen. The day view covers it.
- **Day view (fixes Audit's info item):** the local text, then `SyncDraftCopy.blockedDay` under it. A blocked day with pending edits shows the blocked line too.

### 6. A conflict found after saving (E6 re-check)
It's the same screen, the same rows and the same choices. Only the heading changes, because this text was already saved:
- One: **"Your reflection for November 20 was also changed elsewhere."**
- Several: **"3 reflections were also changed elsewhere."**
- The line under it is the same as §1.
- Use this heading only when every row came from the re-check. If any row came from connecting, use §1's heading.
- It never opens on its own while the person is writing. It's reached from the Today line below.

### Coming back later (both cases)
- **Today line**, while any choice is still open, until it's tapped or dismissed:
  - One: "Your reflection from November 20 was also changed elsewhere. Choose what to keep."
  - Several: "2 reflections were also changed elsewhere. Choose what to keep."
  - Tapping it opens this screen. Dismissing it changes nothing, and the line comes back on the next launch while choices are still open.
- **Day view:** the existing `SyncDraftCopy.alsoChangedElsewhere` line, which opens this screen when tapped.
- None of this uses a modal, badge or tab dot.

### 7. Deleted from your account, changed on this iPhone (Prep, 2026-11-22, Chief P32)
The account no longer has this day, but this iPhone has unsent writing for it. It's a normal row in the choices list, counted in the heading.
- Row title: the date, as §2.
- Under **"Your account"**: "This day was deleted from your account."
- Under **"This iPhone"**: the local text, as normal.
- Two choices. **Keep this iPhone's** is selected by default, because nothing is removed:
| Choice | Line under it |
|---|---|
| **Keep this iPhone's** | "This day goes back to your account with what you wrote here." |
| **Let it stay deleted** | "What you wrote here goes to Set aside, and this day is removed from this iPhone." |
- The kept text keeps its own privacy setting. No private-wins line.
- **Set aside item** for Let it stay deleted: date, "This day was deleted from your account.", the full text, [Copy]. Never purged automatically.
- **Keep both for all doesn't touch these rows.** It isn't a Keep both case, and putting back a day the person deleted should be a choice they make for that day. After Keep both for all, the screen stays open if any of these rows remain. If these are the only rows left, hide [Keep both for all].
- **Heading:** if every row is this case, use:
  - One: **"November 20 was deleted from your account, but you changed it on this iPhone."**
  - Several: **"3 days were deleted from your account, but you changed them on this iPhone."**
  - Mixed with other rows: §1's heading (or §6's, under §6's rule).
- **Day view:** the local text, then "This day was deleted from your account. What you wrote here is kept on this iPhone." Tapping it opens this screen. It replaces `alsoChangedElsewhere` for this case, since there's only one version.
- The Today come-back line counts these days like any other open choice.

### 8. A day too long to save to your account (Prep, 2026-11-22, Chief P32)
Keep both can make a day longer than your account can hold. That day stays on this iPhone and is never sent. Past days can't be edited, so the fix has to be offered on this screen, before Done.
- **On the row,** when Keep both is selected and the combined text would be too long, add under the choice line: "Together these are too long to save to your account. If you keep both, this day stays on this iPhone only. To save it to your account, keep one instead."
  - Keep both stays allowed and stays the default, because nothing is lost.
- **Keep both for all** skips these rows: they stay on the screen with their choice open. If they're the only rows left, the screen stays open with [Keep both for all] hidden.
- **Day view,** after a too-long day was kept:
  - A past day: "This reflection is too long to save to your account. It's kept on this iPhone only."
  - Today: "This reflection is too long to save to your account. It's kept on this iPhone. Shorten it to save it." Once it's short enough, it saves as normal and the line goes away.
- Set aside never receives anything in this case; both texts are on the day.
- No Today line, badge or modal. It's a settled choice, not an open one.

### 9. Deleted on this iPhone, changed in your account (Prep, 2026-11-22, Chief P34)
This iPhone deleted the day, but your account has a newer edit to it. It's a normal row in the choices list, counted in the heading. It's the mirror of §7.
- Row title: the date, as §2.
- Under **"Your account"**: the account's text, as normal.
- Under **"This iPhone"**: "You deleted this day here."
- Two choices. **Keep your account's** is selected by default, because nothing is removed:
| Choice | Line under it |
|---|---|
| **Keep your account's** | "This day comes back on this iPhone with your account's text." |
| **Delete it everywhere** | "Your account's text goes to Set aside on this iPhone, and this day is deleted from your account." |
- The kept text keeps its own privacy setting. No private-wins line.
- **Set aside item** for Delete it everywhere: date, "You deleted this day here.", the account's full text, [Copy]. Never purged automatically.
- **Keep both for all doesn't touch these rows**, the same as §7: deleting or restoring a day is a choice for that day. The §7 rules for the screen staying open and hiding [Keep both for all] apply here too.
- **Heading:** if every row is this case, use:
  - One: **"You deleted November 20 here, but it was changed in your account."**
  - Several: **"You deleted 3 days here, but they were changed in your account."**
  - Any other mix of rows, including §7 and §9 together: §1's heading (or §6's, under §6's rule).
- **Day view:** the day has no text here, so show only: "You deleted this day here, but it was changed in your account. Choose what to keep." Tapping it opens this screen.
- The Today come-back line counts these days like any other open choice.

### 10. What #16's L1 and L2 look like to the person (Prep, 2026-11-22, Chief P35, event b526506c)
No new copy. These fixes decide which existing row or line the person sees.
- **L1 (deleted from your account, found just before saving):** when the check before saving finds the day was deleted from your account, the day is a §7 row ("This day was deleted from your account.") with §7's choices, default and Set aside item. It must never show the deleted text under "Your account", and it is never marked saved with that text. Heading: §7's own heading when every row is a §7 row, however it was found (corrected 2026-11-22, see §11's heading note). Otherwise §6's rule (re-check rows only → §6 heading; any row from connecting → §1).
- **L2 (blocked day that can be read again, or was deleted):** a day leaves "Can't compare these yet", and its day view drops the `blockedDay` line, as soon as your account's text can be opened or the day is deleted there. It then shows as whatever it now is: a §2 row if the texts differ, a §7 row if deleted with unsent writing here, or nothing at all if there's no choice to make. An older unreadable version must never bring a day back under "Can't compare these yet".
- Acceptance 6 covers both: neither case may leave a day in conflict without a row or a day-view line.

### 11. "Learn more" page for the spec A sheet (Prep, 2026-11-22, Sous request event 748bac8c)
Reached from the spec A sheet's "Learn more" link and from Settings → Privacy. Final copy; it replaces Growth's draft surface 2 (`PLANS/GRATEFUL_DAY_IOS_PRIVACY_COPY_DRAFT_2026_11_21.md`). Growth may tune wording only if every fact stays. Facts from Audit's baseline (`RESEARCH/GRATEFUL_DAY_IOS_PRIVACY_SECURITY_BASELINE_2026_11_21.md`, findings 2–3).

One scrolling page. No buttons except the standard back or close. Opening it from the sheet and coming back leaves the sheet as it was; nothing is accepted or published by reading this page.

**Heading:** **What's private in your journal**

**Intro:** "The words you write are encrypted. The dates and times you save or edit an entry can be seen by others."

**Encrypted**
"The words of your private reflections. They can only be read with your journal key."

**Can be seen by others**
"Anyone who looks up your account can see:"
- "Which days you wrote on."
- "When you saved each reflection, and each time you edited it."
- "Roughly how long each reflection is."

"They can't see what you wrote."

**Public reflections**
"Anyone can read a reflection you make public. If you make it private later, earlier public versions may still be readable. Making it private protects what you save from now on."

**Your journal key**
"Your journal key opens every private reflection saved to your account, including earlier versions. Anyone who gets your journal key, now or years from now, can read all of them. Keep it safe and keep a backup. If it's lost and there's no backup, your private reflections can't be opened again."

**Deleting**
"Deleting a reflection asks for it to be removed from your account. Most places that store it will remove it, but some may keep a copy."

**Before you connect an account**
"Before you connect an account, your reflections stay on this iPhone only. They aren't in iCloud or iPhone backups, so they're lost if the phone is." (Seth-decided copy, MVP doc, "Local drafts are not backed up".)

**Rules**
- Section titles are headings for VoiceOver.
- Never "Without your key, no one can read them", "only you can read them", or any banned phrase in Growth's draft.
- No relay, event, NIP, nsec or "secret key" terms.
- The Settings → Privacy guarantee line (see Open) is added to this page only when Seth turns it on.

**Acceptance**
1. The page states all four spec A facts: save and edit times, rough length, earlier public versions can stay readable, and anyone who gets the key later can read the whole history.
2. The same page opens from the sheet and from Settings → Privacy.
3. Reading it doesn't accept the sheet, publish anything, or change any setting.

**Heading note (answers Sous, same event):** when every row on the screen is a §7 row, use §7's heading, whether the rows were found on connecting or by the check before saving. "Was also changed elsewhere" is wrong for a deletion; §10's earlier wording was my error and is corrected above. The same goes for §9: all §9 rows → §9's heading. §6's heading is only for re-check rows that are §2 rows, and any mix follows §6's rule.

### 12. Guest writing for a day you deleted (Prep, 2026-11-22, Chief P40, Audit #17 M1)
A day was written on this iPhone before connecting, and the person had deleted that day under their account. The sort keeps the day deleted, publishes nothing, and puts the guest text in Set aside.
- **Set aside item:** date, then the reason **"Written before you connected your account. You'd deleted this day, so it wasn't put back."**, then the full text and [Copy]. It's never purged automatically.
- There's no row on the conflict screen, no day-view line and no Today line. The person already chose to delete the day, so this isn't an open choice.

### Acceptance
1. Every word from both sides ends up on that day or in Set aside, including after Not now, Done and Keep both for all.
2. Nothing is published for a conflicting day until its choice is applied. Nothing is ever published for a blocked day from this screen.
3. Both labels appear on every row, and VoiceOver reads them.
4. A combined day is private if either text was private, and says so before Done.
5. No relay, event, sync or key terms appear anywhere on the screen.
6. No day sits in conflict, or unsent because it's too long, without a row on this screen or a line in its day view (P32).

## Open
- Guarantee line for Settings → Privacy (after device checks): "A backup copy of your journal key is kept in iCloud Keychain, which Apple encrypts end to end. Anyone who can sign in to your Apple account on a trusted device could restore it." Prep approves this wording. Seth turns it on.

## Save-triggered publishing copy (added 2026-11-22, Prep; PR #21)

Final copy. The source is `PLANS/GRATEFUL_DAY_IOS_KEY_EXPORT_AND_SAVE_SYNC_PRODUCT_2026_11_22.md` §2.3. It's implemented in `DisclosureCopy` on #21 at b1da6dc.
- **Spec A sheet** goes after the count line, and is shown on its own when the count is 0: "After this, what you write is backed up to your account automatically."
- **Learn more → "Can be seen by others"** goes after "They can't see what you wrote.": "Grateful Day backs up a reflection a little while after you stop writing, so one sitting usually shows as one edit."
- **Accounts that already accepted the sheet** aren't shown it again (D5, pending Seth).
