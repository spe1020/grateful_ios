# V5 (M5b-1) journal store fixture

`v5-journal.store` was written by the **M5b-1 build** (`phase1/m5b1-sync-read` at
`53b51e0`, schema `JournalSchemaV5`) **before** any M5b-2 model change, so the
V5→V6 migration test opens a real V5 store, not one built from today's classes.
It was written by a temporary test in that worktree, which was then deleted;
the WAL was checkpointed (empty) and the file is in WAL mode like the V4 one.

Contents (America/Chicago):
- 2026-11-19: guest row "Guest note"
- 2026-11-20: row owned by `bbbb…` (64 × "b"): "Synced note", state `synced`,
  remote event id 64 × "c", remote created_at 1795190000
- account marker for that pubkey, state `connected`
- one surfaced `EarlierVersion` for 2026-11-20: "Earlier note", reason `replacedByRemote`
- flag `reminderOfferShown`

Never regenerate it with newer code.
