# V4 (M5a) journal store fixture

`v4-journal.store` was written by the **M5a build** (`main` at `f93dc54`, schema
`JournalSchemaV4`) **before** any M5b-1 model change, so the V4→V5 migration test
opens a real V4 store, not one built from today's classes.

Contents (America/Chicago):
- 2026-11-19: guest row "Guest note"
- 2026-11-20: row owned by `aaaa…` (64 × "a"): "Owned note"
- account marker for that pubkey, state `signedOut`
- milestone 1 acknowledged; flag `reminderOfferShown`

The WAL was empty when copied. Never regenerate it with newer code.
