# Photos Database Inspector — Handover

## Status

**Phase 2 — asset record inspection implemented, not yet verified on device.**

- Phase 1 (schema discovery): `DONE`, verified by a real device scan (see below).
- Phase 2 (asset record dump + comparison): `CODE COMPLETE`, awaiting the first on-device run.

Last updated: 2026-09-22.

## Project purpose

This repository is an isolated experiment tool for investigating how iOS 15 Photos represents assets
internally. The motivating question is whether the Photos Screenshot classification is stored in
internal database metadata rather than being derived only from the image file's EXIF/metadata.

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
- No database writes in any code path

The filesystem access entitlements are based on the existing iOSCleanerInspector project and are
intended for the user's own TrollStore test device. They are not normal App Store entitlements.

## Phase 1 — verified by device scan

One real scan was performed on the test device and captured to `scan.log` (3306 lines).

Facts taken from that scan, not from assumptions:

- the Photos library database is `/var/mobile/Media/PhotoData/Photos.sqlite`
  - main file `70,176,768` bytes
  - `Photos.sqlite-wal` present, `1,742,792` bytes
  - `Photos.sqlite-shm` present, `32,768` bytes
- device SQLite version: `3.37.0`
- `Photos.sqlite` contains **66 tables**
- **10 tables carry a `ZASSET` column**:
  `ZADDITIONALASSETATTRIBUTES`, `ZASSETANALYSISSTATE`, `ZCLOUDRESOURCE`,
  `ZCOMPUTEDASSETATTRIBUTES`, `ZDETECTEDFACE`, `ZEXTENDEDATTRIBUTES`, `ZFACECROP`,
  `ZINTERNALRESOURCE`, `ZLEGACYFACE`, `ZMEDIAANALYSISASSETATTRIBUTES`
- `ZASSET` has classification columns `ZKIND`, `ZKINDSUBTYPE`, `ZSAVEDASSETTYPE`
  and identity columns `ZUUID`, `ZFILENAME`, `ZUNIFORMTYPEIDENTIFIER`, `ZDIRECTORY`
- the name heuristic in Phase 1 hit exactly one `screen`-containing column:
  `ZMEDIAANALYSISASSETATTRIBUTES.ZSCREENTIMEDEVICEIMAGESENSITIVITY`

## Phase 2 — implementation

`PhotoDatabaseInspector` gained three read-only entry points:

| method | purpose |
| --- | --- |
| `assetListReportWithLimit:` | newest `ZASSET` rows + grouped `ZKIND`/`ZKINDSUBTYPE`/`ZSAVEDASSETTYPE` census |
| `assetDumpReportForSearch:` | one asset expanded into `ZASSET` + all referencing tables |
| `assetCompareReportForSearches:` | field-by-field diff of several assets |

`ViewController.m` gained an `Asset Inspector` screen with a database path field, a search
field, and `Asset list` / `Dump asset` / `Compare` / `Export` actions. Phase 1 is unchanged and
still reachable from the root screen.

Design decisions, and why:

1. **Child tables are discovered from the schema, not hard-coded.** Any table with a `ZASSET`
   column is treated as a child of the asset row. This survives schema changes between iOS versions.
2. **A second hop is resolved by a naming rule:** if a column name is also an existing table name
   (`ZADDITIONALASSETATTRIBUTES.ZASSETDESCRIPTION` → `ZASSETDESCRIPTION`), that row is fetched too.
3. **`ZASSET.ZMASTER` and `ZASSET.ZIMPORTSESSION` are dead on iOS 15.** Both columns exist, but
   `ZMASTER` and `ZIMPORTSESSION` are not tables in this schema. Any hard-coded join on them
   would have failed silently; the tool skips them and prints the reason.
4. **`RELATION CHECK`** prints, for every `ZASSET` column that resolves to a table, the column
   value next to the row found through `ZASSET = <Z_PK>`, marked `MATCH` / `MISMATCH`. This
   verifies the join direction instead of assuming it.
5. **`DIFF BLOCK`** is a stable `TABLE.COLUMN = value` listing (multi-row tables indexed
   `TABLE[0]`, `TABLE[1]`, …) so the exported reports of two assets can be diffed line by line.
6. **No `PRAGMA journal_mode`, no checkpoint.** The WAL sidecars are `stat`-ed for size only.
   `sqlite3_busy_timeout` is set on the connection (a connection setting, not a write) so a
   concurrent Photos daemon makes the read wait instead of failing with `SQLITE_BUSY`.

## Things NOT established yet

The following are hypotheses, not findings:

- that a field named `ZSCREENTYPE` exists on iOS 15 (the scan found none)
- that `ZSCREENTIMEDEVICEIMAGESENSITIVITY` has anything to do with screenshots
  (it lives in `ZMEDIAANALYSISASSETATTRIBUTES`; the name is a lead, nothing more)
- that one field alone controls the Screenshot classification
- that the classification lives in `ZASSET`
- that the classification lives in `ZADDITIONALASSETATTRIBUTES`
- that modifying Photos.sqlite would survive Photos daemon reconciliation
- that a read-only SQLite connection actually sees the contents of the present `-wal` file
  on this device (the sidecar exists, but that was not verified by comparing row counts
  before/after a Photos write)

Do not turn any of these into project facts without device evidence.

## Next experiment: on-device sample comparison

Sample set (prepared by hand on the device):

- **A** native iOS Screenshot (power + volume up)
- **B** ordinary PNG imported into Photos
- **C** ordinary HEIF/JPEG photo
- **D** optional: a re-saved copy of the same visual content

Then, in `Asset Inspector`:

1. `Asset list` → record the class census and confirm which `(ZKIND, ZKINDSUBTYPE, ZSAVEDASSETTYPE)`
   group each sample falls into.
2. `Dump asset` for A, B, C → export all three reports.
3. `Compare` with `A,B,C` → the differing fields are listed directly.
4. Repeat with more samples before treating any field as the classification.

Record for every candidate field:

- database path, table, primary key / asset identifier
- column name, value per sample
- whether the difference is stable across additional samples
- whether the field is *derivable* from the file itself (EXIF/UTI), i.e. whether it could be
  the stored classification or just a cached derivation of it

## WAL warning

The scanner reports the presence of `.sqlite-wal` and `.sqlite-shm`. It does not checkpoint,
vacuum, or otherwise modify the database. Phase 2 opens the database with
`SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX` and never issues `PRAGMA journal_mode=…`,
`PRAGMA wal_checkpoint`, `VACUUM`, or any DML/DDL.

SQLite read-only behaviour against a live WAL still has to be verified on the device. If a
consistent snapshot becomes necessary, design that as a separate experiment; do not silently
introduce a write-capable checkpoint.

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

If an earlier conclusion is disproved, preserve the old record and mark it `RETRACTED` rather
than silently rewriting history.
