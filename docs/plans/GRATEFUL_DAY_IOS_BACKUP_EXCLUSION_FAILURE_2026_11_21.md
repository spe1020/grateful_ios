---
title: "Grateful Day iOS: Backup-Exclusion Failure Behavior (evaluation and required handling)"
tags: [grateful-day, ios, privacy, backup, m3]
status: active
created: 2026-11-21
---

Requested by Seth, #general event 35ef16eb (2026-11-21): "ensure the backup-exclusion failure behavior is explicitly evaluated and documented. We should not promise stronger privacy protections than the implementation can verify."
Owner of this doc: Chief (coordination). Implementation: Sous (M3a). Verification: Audit. Copy: Prep (+ Growth).

## What the code does today (grateful_ios main, merged via #7 at c8c7a2e)
- `StoreLocation.prepare()` sets `isExcludedFromBackup = true` on `Application Support/GratefulDay/Store/` on every launch (`App/GratefulDay/Storage/StoreLocation.swift`).
- If that call throws, it returns `backupExclusionApplied: false`. `JournalStore.openIfPossible` stores `backupExclusionFailed = true` and **opens the store anyway** (`JournalStore.swift:55`).
- Nothing reads `backupExclusionFailed` outside tests. No log line (Audit M2 L1). No UI change.
- Setting `.complete` protection on the directory uses `try?`, so a failure there is also silent. (`protectFiles()` after open does throw.)

## Why it matters
When exclusion fails, the journal folder is backed up like any other app data: iCloud Backup and Finder backups would contain reflection text.
On that device, the approved pre-account statement ("Your reflections ... aren't included in iCloud or iPhone backups") is **false**. That is exactly the over-promise Seth ruled out.

Likelihood: low (the call fails in edge cases such as a missing/recreated directory or a file-system error), and it is retried each launch. Low likelihood does not make the claim true on the affected device.

## Options considered
1. **Refuse to open the store.** Rejected. It locks the user out of their only copy of their journal, a worse harm than being backed up. Storage doc §2 already rejected this.
2. **Open and say nothing (current).** Rejected. The UI makes a privacy claim that is false on this device.
3. **Open, retry, and stop claiming exclusion while it is not in effect.** Chosen (Chief decision P10, reversible; it reduces a claim, it adds none).

## Required handling (P10), lands in M3a
1. **Log** the failure with no journal content (error domain/code only). Closes Audit M2 L1.
2. **Retry** on every foreground/open, not just cold launch; clear the flag when a retry succeeds.
3. **Surface the flag** to the UI. While `backupExclusionFailed` is true:
   - Settings → Privacy and the Today "On this iPhone only" sheet must NOT say reflections are excluded from backups. They show a short alternate statement instead (Prep writes it; facts: we couldn't keep this iPhone's journal out of backups, it may be included in iCloud/iPhone backups, we'll keep trying).
   - Nothing else changes; writing never blocks.
4. **Tests:** inject a failing exclusion; assert the store opens, the flag is set, a content-free log entry is written, the alternate copy shows, and the flag clears after a successful retry.
5. **Protection-class failures (P10.5, amended per Audit event 2e0a0865):** folder attribute (`try?`, silent) and `protectFiles()` (throws after open → `state = .failed`, locking the user out; Medium defect on main 584a4a2, availability only, no data loss). Required: keep the journal open; log content-free (file name + error code); separate `protectionFailed` flag, retried every foreground and cleared on success; NO UI state (no approved copy claims locked-encryption, so nothing to retract); the flag blocks any future "encrypted" claim; test with an injected failing setter (store opens, flag set, clears on next good foreground).

## What we can and cannot claim (until device verification)
- Simulator tests prove the attribute is set and re-applied. They do NOT prove a real iCloud/Finder backup omits the folder, that SQLite sidecars are covered, or Quick Start behavior. These stay **mandatory release gates** (Seth, event 35ef16eb), owned by Audit, run on a physical device.
- Until those gates pass, store/marketing copy must not claim backup exclusion; in-app copy may state it because it is what the app does, and with P10 it is withdrawn on any device where the call fails.

## Tracking
- Sous: items 1–5 in M3a (`phase1/m3a-today-editor`).
- Prep (+Growth): alternate statement copy.
- Audit: verify 1–5 in the M3a review; update `PLANS/GRATEFUL_DAY_IOS_STORAGE_BACKUP_RECOMMENDATION_2026_11_21.md` §2 to replace "logged ... diagnostic flag" with this behavior (Sous edits, Audit validates).
