# Photos Database Inspector — Handover

## Status

**Phase 1 — read-only Photos database discovery and schema inspection.**

Status: `IN PROGRESS`

## Project purpose

This repository is an isolated experiment tool for investigating how iOS 15 Photos represents assets internally. The motivating question is whether the Photos Screenshot classification is stored in internal database metadata rather than being derived only from the image file's EXIF/metadata.

This repository must not assume the answer in advance.

## Verified project facts

- Target deployment: iOS 15.0+
- Architecture: arm64 via the device toolchain
- Distribution/testing model: TrollStore
- Build system: Makefile + `xcrun --sdk iphoneos clang`
- CI: GitHub Actions on a macOS runner
- Output: `build/PhotosDatabaseInspector.tipa`
- SQLite access: system `libsqlite3`
- Database access: `SQLITE_OPEN_READONLY`
- Current implementation performs no database writes

The filesystem access entitlements are based on the existing iOSCleanerInspector project and are intended for the user's own TrollStore test device. They are not normal App Store entitlements.

## Phase 1 implementation

`PhotoDatabaseScanner`:

1. checks `/var/mobile/Media/PhotoData`
2. recursively finds `.sqlite` and `.sqlite3` files
3. reports `-wal` and `-shm` sidecars
4. passes each database to `PhotoDatabaseInspector`

`PhotoDatabaseInspector`:

1. opens the database with `SQLITE_OPEN_READONLY`
2. reads `sqlite_master`
3. enumerates table schemas with `PRAGMA table_info`
4. applies a column-name heuristic for screenshot/media-related names
5. explicitly reports the read-only safety state

## Things NOT established yet

The following are hypotheses, not findings:

- that a field named `ZSCREENTYPE` exists on iOS 15
- that `ZSCREENTYPE` means "Screenshot"
- that one field alone controls the Screenshot classification
- that the classification lives in `ZASSET`
- that the classification lives in `ZADDITIONALASSETATTRIBUTES`
- that modifying Photos.sqlite would survive Photos daemon reconciliation

Do not turn any of these into project facts without device evidence.

## Next experiment: Phase 2

Use a real iOS 15 device and create a controlled sample set:

- A: native iOS Screenshot
- B: ordinary PNG imported into Photos
- C: ordinary HEIF imported into Photos
- D: optionally, a second copy/re-save of the same visual content

For each asset, identify its Photos record and compare the corresponding rows across the database and related tables.

The objective is a **field-by-field diff**, not a search for one predetermined field.

Record:

- database path
- table
- primary key / asset identifier
- column name
- value for each sample
- whether the difference is stable across multiple samples

## WAL warning

The scanner reports the presence of `.sqlite-wal` and `.sqlite-shm`. It does not checkpoint, vacuum, or otherwise modify the database.

SQLite read-only behavior should be verified on the actual device. If a consistent snapshot becomes necessary, design that as a separate experiment; do not silently introduce a write-capable checkpoint.

## Handover protocol

Every future agent must read:

1. `README.md`
2. this document
3. the current Git history

After making changes, update this document with:

- date
- phase
- code changes
- device verification performed
- findings
- things still unverified
- next recommended experiment

If an earlier conclusion is disproved, preserve the old record and mark it `RETRACTED` rather than silently rewriting history.
