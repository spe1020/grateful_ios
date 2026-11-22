# M4 journal store fixture

`m4-journal.store` was written by the **M4 build** (`phase1/m4-wisdom-reminder` at
`fe72ad4`, schema `JournalSchemaV3`) **before** any M5a model change, so migration
tests open a real M4-era store rather than one built from today's classes
(Audit, PR #11 review).

Contents (all guest entries, America/Chicago):
- 2026-11-19: "First note\n\nSecond note"
- 2026-11-20: "Morning light"
- 2026-11-21: deleted (tombstone, empty text)
- milestone 1 acknowledged
- flag `reminderOfferShown`

The WAL was empty when copied, so the single file holds all data. Never regenerate
it with newer code.
