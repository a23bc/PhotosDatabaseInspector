# PhotosDatabaseInspector

A small **read-only** iOS 15+ TrollStore utility for inspecting the SQLite databases under `/var/mobile/Media/PhotoData/`.

The project is intentionally independent from the larger `iOSCleanerInspector` app. It is an experiment tool for determining what Photos stores about assets, especially the differences between a native Screenshot asset and an ordinary imported image.

## Current scope

### Phase 1 — schema discovery (`Scan Photos DB`)

- recursively locate `.sqlite` / `.sqlite3` databases below `PhotoData`
- report matching `-wal` / `-shm` sidecars
- open each database with SQLite read-only mode
- enumerate `sqlite_master`
- enumerate every table with `PRAGMA table_info`
- flag column names that may be related to screenshots/media/import/capture
- export the raw report through the iOS share sheet

### Phase 2 — asset record inspection (`Asset Inspector`)

- `Asset list` — the newest `ZASSET` rows plus a census grouped by
  `ZKIND` / `ZKINDSUBTYPE` / `ZSAVEDASSETTYPE` (with a sample file name per group),
  so it is visible whether screenshots form their own class
- `Dump asset` — one asset, expanded: the `ZASSET` row, **every table that carries a
  `ZASSET` column**, and one further hop for columns whose name is also a table name
  (for example `ZADDITIONALASSETATTRIBUTES.ZASSETDESCRIPTION` → `ZASSETDESCRIPTION`)
- `Compare` — two or more search terms (comma separated) produce a field-by-field diff
  of the union of all fields, showing only the differing ones
- every dump ends with a `DIFF BLOCK` of stable `TABLE.COLUMN = value` lines, so two
  exports can also be compared outside the app with `diff`
- values are printed with their type context: Core Data `TIMESTAMP` columns are
  converted from the 2001-01-01 epoch, blobs are shown as a hex prefix plus their
  real length (`ZORIGINALHASH`, `ZFACEREGIONS`, …)
- the exact SQL and its bound values are printed in the report, so a result can be
  reproduced by hand

`Dump asset` accepts a file name fragment, a `ZUUID`, a numeric `Z_PK`, or a fragment
of `ZADDITIONALASSETATTRIBUTES.ZORIGINALFILENAME`.

**No database write operation is implemented.** There is no INSERT, UPDATE, DELETE, schema change,
`journal_mode` change, checkpoint, or vacuum operation in either phase. `-wal` / `-shm` sidecars are
only `stat`-ed for their size; they are never opened, modified or checkpointed by this tool.

## Build

The project deliberately does not use an Xcode project, CocoaPods, or Swift Package Manager. GitHub Actions builds it on a macOS runner with the iPhoneOS SDK:

```sh
make package
```

The result is:

```text
build/PhotosDatabaseInspector.tipa
```

The same command is used by `.github/workflows/build.yml`.

## Install / test

Build the TIPA in GitHub Actions, download the artifact, and install it with TrollStore on the test device.

The app expects the same unrestricted filesystem access model as the existing iOSCleanerInspector project. The entitlements are intentionally kept in the repository so the build is reproducible.

## Running the Phase 2 experiment

1. Prepare the samples on the device:
   - **A** a native iOS screenshot (power + volume up)
   - **B** an ordinary PNG imported into Photos
   - **C** an ordinary HEIF/JPEG photo
2. `Asset list` — check the class census and note the file names.
3. `Dump asset` for each sample and export the report.
4. `Compare` with all three names to get the differing fields directly, or diff the
   `DIFF BLOCK` sections of the exported texts.

## Important experimental rule

Do not interpret a column name such as `ZSCREENTYPE` as proof that it is the Screenshot flag.
A schema-level name match is a lead, not a finding; a value difference between two assets is an
observation, not a proof. Phase 2 compares real assets on a real device — see
`docs/PHOTOS_DATABASE_HANDOVER.md` for what has actually been established so far.
