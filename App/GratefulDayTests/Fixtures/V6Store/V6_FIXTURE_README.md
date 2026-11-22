# V6 (M5b-2) journal store fixture

`v6-journal.store` was written by the **M5b-2 build** (`phase1/m5b2-publish` at
`4a3295f`, schema `JournalSchemaV6`, the head Audit passed in #15) **before** any
M6 model change, so the V6→V7 migration test opens a real V6 store. It was
written by a temporary test in that worktree, which was then deleted. The WAL
was checkpointed (empty), and the file stays in WAL mode like the V4 and V5 ones.

Contents (America/Chicago):
- 2026-11-19: guest row "Guest note"
- 2026-11-20: row owned by `bbbb…` (64 × "b"): "iPhone note", state `conflict`,
  remote event id 64 × "c", remote created_at 1795190000
- account marker for that pubkey, state `connected`
- one surfaced `EarlierVersion` for 2026-11-20: "Account note", reason
  `remoteInConflict`, event id 64 × "d" (V6 has no privacy or created_at for it)
- one `OutboxEvent` for 2026-11-20, id 64 × "e", `supersededByRemote`, acked by
  `wss://nos.lol`
- flag `reminderOfferShown`

Never regenerate it with newer code.
