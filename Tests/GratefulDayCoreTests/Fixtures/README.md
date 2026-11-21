# Web interop fixtures

Generated on 2026-11-21 by running the web app's own code from `spe1020/gratefulday` at
commit `a33f42c` (Node, `vite-node`, the repo's `node_modules`). Nothing here was typed by hand.

| File | Produced by |
|---|---|
| `web_events.json` | `entryNotes`, `gratitudeUtils`, `privacyUtils` (NIP-44 via Nostrify `NSecSigner`) and `appSettings`. 36669 tags mirror `DayDetailDialog.tsx` `buildEntryEvent`, which builds them inline; the kind 5 shape mirrors `useDeleteGratitudeEntry.ts`. Signed with nostr-tools `finalizeEvent`. Generated with `TZ=America/Chicago`. |
| `web_dates.json` | `formatDateString`, `getDayOfYear`, `getDateFromDayOfYear`, `formatDisplayDate`, run once per time zone (Honolulu, Kiritimati, UTC, New York, London, Kolkata). |
| `wisdom_samples.json` | `getWisdomForDate` for every local date 2026-09-01 … 2027-12-31. |
| `../../../Sources/GratefulDayCore/Resources/wisdom.json` | `src/lib/wisdom.ts` schedules and items. |

**Test key:** events are signed with a deliberately public key whose secret is
`sha256("grateful-day-ios-fixture-key-v1")`. It is test-only; never use it for anything real.

**Not covered here:** capturing events from a running browser session (the fixtures come from the
same functions the browser runs, but not through the UI), and the `client` tag web adds on https.
The generator script lives in the Phase 0 PR description so it can be re-run.
