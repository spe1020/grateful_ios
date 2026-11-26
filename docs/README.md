# Grateful Day iOS: project documents

Code comments in this repository refer to these documents by short names, such as "interop spec §1.8" or "design r3.1 §3". This folder holds those documents so the references can be resolved from the repository alone.

Files keep the names they had in the team workspace. A comment that cites `PLANS/<NAME>.md` refers to `docs/plans/<NAME>.md`, and one that cites `RESEARCH/<NAME>.md` refers to `docs/research/<NAME>.md`.

**Snapshot:** copied 2026-11-25 against iOS main `10ae4d6` and web main `2b15ce6`. Once this PR is merged, the copies here are the source of truth, and updates come through focused PRs.

**Contents:** no private keys, nsecs or journal plaintext. Message IDs and `buzz://` links point to the team's coordination channels. Readers outside the team can't open them; they're kept as provenance.

## Short names used in code

| Name in code | Document |
|---|---|
| interop spec (r3) | [plans/GRATEFUL_DAY_36669_30078_INTEROP_SPEC_2026_11_21.md](plans/GRATEFUL_DAY_36669_30078_INTEROP_SPEC_2026_11_21.md) |
| design r3.1 (key storage and backup design) | [plans/GRATEFUL_DAY_IOS_KEY_STORAGE_BACKUP_DESIGN_2026_11_21.md](plans/GRATEFUL_DAY_IOS_KEY_STORAGE_BACKUP_DESIGN_2026_11_21.md) |
| storage recommendation | [plans/GRATEFUL_DAY_IOS_STORAGE_BACKUP_RECOMMENDATION_2026_11_21.md](plans/GRATEFUL_DAY_IOS_STORAGE_BACKUP_RECOMMENDATION_2026_11_21.md) |
| M5 flows and copy (`AccountCopy.swift`) | [plans/GRATEFUL_DAY_IOS_M5_FLOWS_AND_COPY_2026_11_21.md](plans/GRATEFUL_DAY_IOS_M5_FLOWS_AND_COPY_2026_11_21.md) |
| Chief P-numbers (e.g. P10, P17) | [plans/GRATEFUL_DAY_IOS_PHASE1_PLAN_2026_11_21.md](plans/GRATEFUL_DAY_IOS_PHASE1_PLAN_2026_11_21.md), the decision log |
| relay reliability write-up | [research/GRATEFUL_DAY_IOS_RELAY_RELIABILITY_2026_11_22.md](research/GRATEFUL_DAY_IOS_RELAY_RELIABILITY_2026_11_22.md) |

## Plans, decisions and specs

- **Phase 1 plan and decision log:** `plans/GRATEFUL_DAY_IOS_PHASE1_PLAN_2026_11_21.md`
- **Phase 1 scope and MVP:** `plans/GRATEFUL_DAY_IOS_PHASE1_SCOPE_2026_11_21.md`, `plans/GRATEFUL_DAY_IOS_MVP_RECOMMENDATION_2026_11_21.md`
- **Account isolation (web #44, iOS #27):** `plans/GRATEFUL_DAY_ACCOUNT_ISOLATION_RECOMMENDATION_2026_11_24.md`, plus the post-merge audit in `research/GRATEFUL_DAY_ACCOUNT_ISOLATION_POSTMERGE_AUDIT_2026_11_25.md`
- **Key export (Show journal key) and save-triggered publishing:** `plans/GRATEFUL_DAY_IOS_KEY_EXPORT_AND_SAVE_SYNC_PRODUCT_2026_11_22.md`, plus the security requirements in `research/GRATEFUL_DAY_IOS_KEY_EXPORT_R3_SECURITY_SIGNOFF_2026_11_23.md`
- **Backup exclusion:** `plans/GRATEFUL_DAY_IOS_BACKUP_EXCLUSION_FAILURE_2026_11_21.md`
- **Phase 1 risk reconciliation (§8) and teachings licensing (§9):** `research/GRATEFUL_DAY_PHASE1_RISK_RECONCILIATION_AND_TEACHINGS_LICENSING_2026_11_25.md`
- **Privacy and security baseline:** `research/GRATEFUL_DAY_IOS_PRIVACY_SECURITY_BASELINE_2026_11_21.md`

## Testing

- **Phase 1 physical-device checklist:** `plans/GRATEFUL_DAY_PHASE1_DEVICE_CHECKLIST.md`
- **Recovery and remaining device tests (current):** `plans/GRATEFUL_DAY_PHASE1_RECOVERY_RUN_SHEET_2026_11_25.md`
- **Superseded, kept for history:** `plans/GRATEFUL_DAY_PHASE1_DEVICE_RUN_SHEET_2026_11_24.md` and `plans/GRATEFUL_DAY_DEVICE_TEST_SCRIPTS_WEB_DECRYPT_AND_KEYCHAIN_RECOVERY.md`

New run sheets go into this folder through their own PRs: the simulator scenario record, the background/foreground interruption sheet, and the refreshed recovery sheet.

## Not copied here

Per-PR audit reports and probe patches stay in the team workspace. Some documents here mention them by path, and those links don't resolve in this repository.
