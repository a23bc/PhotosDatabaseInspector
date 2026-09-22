# PhotosDatabaseInspector

A small **read-only** iOS 15+ TrollStore utility for inspecting the SQLite databases under `/var/mobile/Media/PhotoData/`.

The project is intentionally independent from the larger `iOSCleanerInspector` app. It is an experiment tool for determining what Photos stores about assets, especially the differences between a native Screenshot asset and an ordinary imported image.

Test device: iPhone9,2 (iPhone 7 Plus), iOS 15.8.8 (19H422), TrollStore.

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

A table of the newest `ZASSET` rows. **Tap a row to select a sample.**

- `More` — grows the row limit (50 → 200 → 800 → …, up to all rows)
- `Census` — counts grouped by `ZKIND` / `ZKINDSUBTYPE` / `ZSAVEDASSETTYPE`, with one sample
  file name per group, so it is visible whether screenshots form their own class
- `Detail` — one asset, expanded: the `ZASSET` row, **every table that carries a `ZASSET` column**,
  and one further hop for columns whose name is also a table name (for example
  `ZADDITIONALASSETATTRIBUTES.ZASSETDESCRIPTION` → `ZASSETDESCRIPTION`)
- `Compare` — two or more selected assets produce a field-by-field diff of the union of all
  fields, showing only the differing ones
- reports are shown on a `Report` screen with `Copy` and `Share…`; every dump also ends with a
  `DIFF BLOCK` of stable `TABLE.COLUMN = value` lines, so two exports can be diffed with `diff`
- values are printed with type context: Core Data `TIMESTAMP` columns are converted from the
  2001-01-01 epoch, blobs are shown as a hex prefix plus their real length (`ZORIGINALHASH`,
  `ZFACEREGIONS`, …)
- the exact SQL and its bound values are printed in the report, so a result can be reproduced by hand
- `RELATION CHECK` prints the `ZASSET` to-one column value next to the row found through
  `ZASSET = <Z_PK>`, marked `MATCH` / `MISMATCH`, instead of assuming the join direction

**No text input anywhere in the UI.** Version 0.2.0 had a path field and a search field; showing
the keyboard crashed it inside CoreImage (`CI::GLContext`), with no frame of this app in the stack
other than `main`. See `docs/PHOTOS_DATABASE_HANDOVER.md` and the crash report in `logs/`.

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

`PhotosDatabaseInspector.entitlements` must stay at the repository root — the Makefile reads it from
there, so moving it breaks the CI build.

## Install / test

Build the TIPA in GitHub Actions, download the artifact, and install it with TrollStore on the test device.

The app expects the same unrestricted filesystem access model as the existing iOSCleanerInspector project. The entitlements are intentionally kept in the repository so the build is reproducible.

## Running the Phase 2 experiment

1. Prepare the samples on the device:
   - **A** a native iOS screenshot (power + volume up)
   - **B** an ordinary PNG imported into Photos
   - **C** an ordinary HEIF/JPEG photo
2. `Asset Inspector` — the newest assets are at the top of the table. `Census` shows the populations.
3. Tap A, B and C, then `Compare` to get the differing fields directly, or `Detail` on one asset and
   diff the `DIFF BLOCK` sections of the exported reports.

`logs/` holds the device evidence: `scan.log` (Phase 1 scan) and the 0.2.0 crash report.

## Important experimental rule

Do not interpret a column name such as `ZSCREENTYPE` as proof that it is the Screenshot flag.
A schema-level name match is a lead, not a finding; a value difference between two assets is an
observation, not a proof. In particular, `ZKINDSUBTYPE=10` correlates with `public.png` in the first
census — that may just mean "PNG".
