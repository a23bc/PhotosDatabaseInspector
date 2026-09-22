# Photos Database Inspector — Handover

## Status

**Phase 2 — asset record inspection works on device; the 0.2.0 UI had to be replaced because it crashed.**

- Phase 1 (schema discovery): `DONE`, verified by a real device scan.
- Phase 2 (asset record dump + comparison): `WORKS` (0.2.0 produced a full asset list on the device).
- Phase 2 UI with text input: **`RETRACTED`** — see "Crash" below.
- Sample comparison of A/B/C: **`NOT DONE YET`**.

Last updated: 2026-09-22.

## Test device

- model code `iPhone9,2` (iPhone 7 Plus)
- iOS **15.8.8 (19H422)**
- TrollStore installation of `build/PhotosDatabaseInspector.tipa`

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
- `PhotosDatabaseInspector.entitlements` must stay at the repository root: the Makefile reads it from there
- local build artifacts are kept as `build/ci/PhotosDatabaseInspector-<version>.tipa`, so several
  versions can sit side by side instead of overwriting one another
- version numbers move slowly: the same phase keeps the same minor version, so a fix after 0.2.0
  becomes 0.2.1, not 0.3.0

The filesystem access entitlements are based on the existing iOSCleanerInspector project and are
intended for the user's own TrollStore test device. They are not normal App Store entitlements.

## Phase 1 — verified by device scan

One real scan was performed on the test device and captured to `logs/scan.log` (3306 lines).

Facts taken from that scan, not from assumptions:

- the Photos library database is `/var/mobile/Media/PhotoData/Photos.sqlite`
  - main file `70,176,768` bytes at scan time
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

## Phase 2 — first on-device run (version 0.2.0)

`Asset list` ran successfully on the device. Observed in its output:

- `ZASSET` total rows: **2827**
- 10 related tables discovered from the schema, in the order the code predicts
- class census (grouped by `ZKIND` / `ZKINDSUBTYPE` / `ZSAVEDASSETTYPE`):

  | ZKIND | ZKINDSUBTYPE | ZSAVEDASSETTYPE | count | sample file |
  | --- | --- | --- | --- | --- |
  | 0 | 10 | 3 | 1972 | IMG_0002.PNG |
  | 0 | 2 | 3 | 584 | IMG_0086.HEIC |
  | 0 | 0 | 3 | 184 | IMG_0084.HEIC |
  | 1 | 0 | 3 | 60 | IMG_0011.MOV |
  | 1 | 103 | 3 | 22 | IMG_0056.MP4 |
  | 1 | 0 | 0 | 3 | IMG_1594.MOV |
  | 0 | 10 | 6 | 1 | 36A0BCD7-5749-4E3B-893A-E2BB2D2AF507.PNG |
  | 1 | 101 | 3 | 1 | IMG_0282.MOV |

  **This is a population, not a labelling.** `ZKINDSUBTYPE=10` correlates with `public.png`, so it may
  simply mean "PNG". It must not be recorded as "screenshot" until the controlled samples say so.

## Crash — version 0.2.0, `EXC_BAD_ACCESS` when a text field was used

Evidence: `logs/PhotosDatabaseInspector-2026-09-22-180234.ips` (0.2.0 build 2, iPhone9,2, iOS 15.8.8).

- exception: `EXC_BAD_ACCESS (SIGSEGV)`, `KERN_INVALID_ADDRESS at 0x0`, `pc = 0`
- the only frame belonging to this app in the whole stack is `main` (frame 79)
- the stack is entirely system code:

  ```text
  UITextSelectionInteraction _handleMultiTapGesture:      (multi-tap inside a text field)
   -> UITextField becomeFirstResponder -> keyboard loads
   -> TUICandidateView prepareForLayoutChange: -> TUICandidateArrowButton -> UIButton layoutSubviews
   -> UIImageView setImage: -> UIImage _imageWithStylePresets:tintColor:traitCollection:
   -> CoreUI CUICatalog imageByStylingImage: -> CUIShapeEffectStack sharedCIContext
   -> CIContext contextWithOptions: -> CI::GLContext::GLContext(...)   <-- crash: call through a NULL pointer
  ```

**Conclusion (what the evidence supports):** showing the keyboard is what killed 0.2.0. The first
time this process renders a CoreUI "styled image" it creates the process-wide shared `CIContext`,
and that construction segfaults on this device/OS. Our own code never appears in the stack, and the
entitlements are not implicated: the same process had already read `Photos.sqlite` successfully.

**Not established:** whether the keyboard is the only trigger. Every UIKit surface that renders a
styled image (SF Symbols, share sheets, alerts) goes through the same `CUIShapeEffectStack` path,
so those remain unverified. The share sheet is suspected to be safe because a report was exported
on 0.2.0, but that was not instrumented.

## Phase 2 UI — version 0.2.1

The UI was rebuilt so that **no screen contains text input**:

- `Asset Inspector` is now a table of assets (`Z_PK`, `ZKIND/ZKINDSUBTYPE/ZSAVEDASSETTYPE`, UTI,
  filename, date). Tapping a row toggles selection; there is no search field.
  - `More` — grows the row limit 50 → 200 → 800 → … (all 2827 rows if needed)
  - `Census` — the grouped census on its own
  - `Detail` — full record dump of the first selected asset
  - `Compare` — field-by-field diff of 2 or more selected assets
- `ReportViewController` shows a report with `Copy` (pasteboard, no UI) and `Share…`.
  Report text views are `selectable = NO`, so no edit menu can appear.
- `UIAlertController` was removed entirely; problems are shown in the status label.
- Samples for the experiment are chosen by tapping rows, so the keyboard is never involved.

`PhotoDatabaseInspector` gained, all read-only:

- `assetOverviewWithLimit:` — structured rows for the table UI (`total`, `count`, `rows`, `error`)
- `assetCensusReport` — the census on its own

Corrections carried in 0.2.1:

- **Date formatting.** 0.2.0 printed `ZDATECREATED=811739210` for some rows and a converted date for
  others. Cause: SQLite's NUMERIC affinity stores a whole-valued REAL as INTEGER, and only the FLOAT
  branch applied the Core Data (2001 epoch) conversion. Both branches now convert, so the same column
  is always rendered the same way. The 0.2.0 output was inconsistent, not wrong data.
- `ZASSET.ZMASTER` and `ZASSET.ZIMPORTSESSION` are referenced by columns but are not tables on
  iOS 15, so child tables are discovered from the schema instead of a hard-coded join list.

## Things NOT established yet

The following are hypotheses, not findings:

- that a field named `ZSCREENTYPE` exists on iOS 15 (the scan found none)
- that `ZSCREENTIMEDEVICEIMAGESENSITIVITY` has anything to do with screenshots
- that `ZKINDSUBTYPE=10` means "screenshot" rather than "PNG"
- that one field alone controls the Screenshot classification
- that the classification lives in `ZASSET` or in `ZADDITIONALASSETATTRIBUTES`
- that modifying Photos.sqlite would survive Photos daemon reconciliation
- that a read-only SQLite connection sees the contents of the present `-wal` file
- that the keyboard is the only way to trigger the CoreImage crash

Do not turn any of these into project facts without device evidence.

## Next experiment

1. Install 0.2.1, open `Asset Inspector`, confirm the table loads and nothing crashes.
2. Cheap falsification test for the crash: reinstall or relaunch 0.2.0 and tap a text field once.
   If it crashes again with the same `CI::GLContext` stack the keyboard trigger is deterministic;
   if not, the failure was environmental (memory / GPU) and the "keyboard" explanation is too narrow.
3. Prepare samples on the device: A native screenshot, B imported PNG, C imported HEIF/JPEG.
   They appear at the top of the asset table because it is ordered by `Z_PK DESC`.
4. Select A, B, C → `Compare` → export. `Detail` on each if the diff needs more context.

For every candidate field record: database path, table, primary key, column name, value per sample,
whether the difference is stable across more samples, and whether the value is *derivable from the
file itself* (EXIF/UTI) — a cached derivation is not the stored classification.

## WAL warning

The scanner reports the presence of `.sqlite-wal` and `.sqlite-shm`. It does not checkpoint,
vacuum, or otherwise modify the database. Phase 2 opens the database with
`SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX` and never issues `PRAGMA journal_mode=…`,
`PRAGMA wal_checkpoint`, `VACUUM`, or any DML/DDL. `sqlite3_busy_timeout(3000)` is a connection
setting, not a write.

Note that the library is live: between two runs the main file grew from `70,176,768` to
`70,180,864` bytes and the WAL shrank from `1,742,792` to `523,272` bytes.

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
