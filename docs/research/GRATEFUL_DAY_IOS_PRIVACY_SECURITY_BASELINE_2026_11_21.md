---
title: "Grateful Day iOS — Privacy & Security Baseline (Audit, pre-draft)"
tags: [grateful-day, ios, audit, privacy, security, nip-44, kind-36669]
status: active
created: 2026-11-21
---

Requested by Chief, #general buzz://message?channel=9a37a94b-4f0e-4237-bbc7-c1fe3a4ee887&id=dca67680f34e8bb09b8849b931611f9f7e5cdb0c92b412cd89117fabf0a74b38
Direction: Seth, buzz://message?channel=9a37a94b-4f0e-4237-bbc7-c1fe3a4ee887&id=ed2f849daeffb8843111738cc56b637520a46e1ca5fce168e4cdcf8ab7a2375d

## Scope
- Read-only: `~/.buzz/REPOS/gratefulday` @ `a33f42c`, `~/.buzz/REPOS/zapcooking_ios` @ `fb1a41f` (Keychain settings only).
- Files: `NIP.md`, `src/lib/privacyUtils.ts`, `src/hooks/useDecryptedEntry.ts`, `src/hooks/useNip44Support.ts`,
  `src/components/DayDetailDialog.tsx` (save/share/delete), `src/hooks/useDeleteGratitudeEntry.ts`,
  `src/lib/entryTombstones.ts`, `src/hooks/useLoginActions.ts`, `src/components/LoginPersistence.tsx`,
  `src/lib/appSettings.ts`, `src/lib/wisdomStore.ts`, `src/hooks/useGratitudeEntries.ts`, `src/App.tsx`.
- Not done: no tests or builds run (discovery only); no Sous draft exists yet; no App Store policy check.
- This is requirements input, not a release assessment. Validation of Sous's spec follows when it exists.

## What the web app does today (verified)
1. **Private entry wire format.** `DayDetailDialog.tsx:472-505`: tags `d`=YYYY-MM-DD, `published_at`=midnight of that day,
   `day`=day-of-year, `["encrypted","nip44"]`, generic `alt`. Content = NIP-44 self-encryption to own pubkey via signer
   (`privacyUtils.ts`). Encrypt failure fails closed (`:556-566`) — good.
2. **Public metadata per private entry:** pubkey, date, day-of-year, `created_at` (actual save time, to the second — every
   edit republishes, so edit times too), presence of the encrypted tag, and approximate length (NIP-44 pads to buckets).
   Anyone can query `kinds:[36669], authors:[pk]`. Exposed: which days you journal, time of day, edit frequency, streaks,
   rough length. Not exposed: content.
3. **No forward secrecy.** All private entries + settings are encrypted to one long-lived key and sit on public relays.
   Deletion is NIP-09, best-effort (`useDeleteGratitudeEntry.ts`); older replaced versions may persist on archival relays.
   A key compromise at any future point exposes the full journal history retroactively.
4. **Web key storage.** Nostrify `NLogin` persists to `localStorage['nostr:login']` and `LoginPersistence.tsx` mirrors it to
   `gratefulday:login-backup:v1`. For nsec logins the secret key is plaintext in browser storage (pre-existing web risk —
   do not copy this pattern).
5. **Settings already sync.** `appSettings.ts`: kind 30078, `d=gratefulday:settings`, NIP-44 encrypted; carries
   `privacyDefault` (LWW), `celebratedMilestones` (union), `lastSeenNotifications` (max). Milestones are NOT local-only
   (correction to the discovery frame); localStorage is a cache.
6. **Local-only:** wisdom history (`wisdomStore.ts`, stores no user writing), tombstones, nip44-support cache, mutes/hides.
7. **Community feed excludes encrypted entries** (`useGratitudeEntries.ts:148`). Private→share has an explicit confirm guard.
8. **Default relays** (`App.tsx:40-44`): damus, nostr.band, nos.lol, primal, nostr.wine. Private entries go to all write relays.
9. **`NIP.md` is stale:** omits the `encrypted` tag, generic alt, blank-line multi-note content, `published_at` semantics,
   and the 30078 settings doc. Two clients cannot interoperate from it as written.

## Requirements for the iOS plan (Audit baseline)
### Key custody
- R1. Secret key only in Keychain, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` (Zap Cooking `NostrKey.swift:163` uses this).
  Never UserDefaults, files, logs, analytics, crash reports, or the pasteboard without `localOnly` + expiry.
- R2. Any iCloud Keychain backup is explicit opt-in with disclosure (ZC `KeychainBackupService.swift` pattern uses
  `AfterFirstUnlock` + synchronizable — a weaker accessibility class; acceptable only as a deliberate choice).
- R3. Remote signer (NIP-46) path: fail closed when NIP-44 unavailable, same as web. No plaintext fallback.
- R4. Because of finding 3, the plan must say how a user backs up and recovers their key, and what loss means
  (losing the key = losing every private entry, permanently).

### Encryption & metadata
- R5. iOS v1 must produce byte-compatible 36669 private entries (same tags, same NIP-44 self-encryption) or web breaks.
- R6. Metadata exposure (finding 2) must be an explicit, recorded decision for iOS — Seth/Prep decide, I recommend:
  v1 matches web format for interop, plus an honest in-app disclosure ("content is encrypted; the days and times you
  write are visible"). Hiding dates (opaque `d`, date inside ciphertext, no `day`/`published_at`) is a spec v2 change to
  BOTH clients; scope it for a later phase, don't do it on one client.

### Local storage
- R7. Local journal store with `NSFileProtectionComplete`. Decide whether the plaintext store is in iCloud device backups
  (not end-to-end unless Advanced Data Protection). For no-account users it may be the only copy — so this is a
  product trade-off, not a default.
- R8. App-switcher privacy cover; optional Face ID lock is a Prep product call.

### Interop (for Sous's 36669 spec)
- R9. Spec must cover everything in finding 9, plus the 30078 settings doc and its reconcile rules (LWW / union / max).
- R10. `d` = the calendar day the entry is for, in the user's local calendar — not derived from `created_at`. Specify
  timezone behavior (travel, editing yesterday after midnight).
- R11. Specify `created_at` for entries written offline and signed later (see below).

## Offline / no-account question
Correction to the framing: `d` is scoped per pubkey, so duplicate `d` tags can't occur. The real risk is **silent
overwrite**: publishing a local entry for a date that already has a relay entry replaces it (newest `created_at` wins),
and if the local one is backdated older, relays silently keep the remote one instead.

Recommendation (Option B — plain local drafts, sign later):
- Local store is the source of truth; the OS encrypts it at rest. Nostr encryption only matters once data leaves the
  device, so "encrypting before a key exists" is unnecessary.
- Nothing is published without a key. Creating or importing a key is an explicit user step ("turn on sync/backup").
- On linking: fetch the pubkey's existing 36669s first; for each date clash, decrypt and merge notes (content is already
  blank-line delimited notes) or ask — never blind-publish. Publish with `created_at = now`.
- Option A (silent key on first launch) is acceptable only with R1/R2/R4 and a backup prompt before the user builds
  history; otherwise device loss = silent total loss. It also leaves an orphan identity if the user later links an existing account.
