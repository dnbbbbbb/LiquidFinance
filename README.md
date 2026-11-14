# LiquidFinance

Native iOS (SwiftUI) personal finance app. **Status: foundation + core ledger + Backup/Restore written; NOT yet compiled or run** (authored on Windows with no Swift toolchain). First step on a Mac: `swift test`, then fix any compile errors.

## Layout
- `Package.swift`, `Sources/LiquidFinanceCore/` — UI-free core (Data, Domain, Backup), unit-testable with `swift test` on macOS.
  - `Data/` SQLite3 wrapper, versioned migrations (`PRAGMA user_version`), FK enforced, atomic transactions with savepoints.
  - `Domain/` `Money` (Int64 minor units), models, `LedgerService` (all money rules), default student categories, settings store.
  - `Backup/` `.lfbackup` format, AES-GCM + PBKDF2, `BackupService` (create/verify/inspect/prepare/restore/rollback/prune).
- `App/LiquidFinance/` — SwiftUI shell. Create an iOS 17+ Xcode App target, add these files, link the package.
- `Tests/` — ledger rules and backup/restore (before/after snapshot comparison).

## Key decisions
- Balances are **derived** (opening + signed effects), never stored → edit/delete cannot desync.
- Transfers, debt principal (`debtIn/debtOut`) and adjustments are excluded from income/expense; transfer fees count as expense; refunds reduce expense.
- `idempotencyKey` (unique) prevents duplicate saves. Accounts/categories with history cannot be deleted (archive).
- Backup container: custom `LFBACKUP` binary (header JSON + archive of `manifest.json`, `database.sqlite`, `attachments/<uuid>`, `integrity.json`) instead of ZIP (no ZIP API in Foundation on iOS without third-party). SHA-256 = integrity only; AES-GCM (header as AAD) = authenticity + confidentiality. Header exposes counts only.
- Restore: verify → stage in temp → validate (integrity_check, foreign_key_check, counts, attachment hashes) → verified pre-restore backup → swap with `restore.inprogress` journal → reopen + verify → commit; any failure or crash rolls back.

## Not implemented (honest list)
Budgets, savings goals, debts UI/logic (tables exist), recurring generation, Analytics/Charts, CSV/PDF export, Merge Restore, accounts/categories management UI, App Lock/Face ID/Keychain (backup password is never stored), notifications, auto-backup (BackgroundTasks), iCloud Drive, dashboard customization, Pink-theme decorative polish, alternate-icon assets & Info.plist entries, localization, UI tests, streaming (large attachments are loaded in memory during backup).
