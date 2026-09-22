# Photos Database Inspector — Handover

## Status

**Phase 2 — asset record inspection works on device; the 0.2.0 UI had to be replaced because it crashed.**

- Phase 1 (schema discovery): `DONE`, verified by a real device scan.
- Phase 2 (asset record dump + comparison): `WORKS` (0.2.0 produced a full asset list on the device).
- Phase 2 UI with text input: **`RETRACTED`** — see "Crash" below.
- Phase 2 UI without text input (0.2.1): `BUILDS GREEN` (CI run `35715762990`, zero compiler
  warnings, artifact `build/ci/PhotosDatabaseInspector-0.2.1.tipa`).
- First sample comparison attempt: **`INCOMPLETE`** — the two exports are analysed in their own
  section below; the export meant to contain the PNG contains HEICs instead, so it has to be
  repeated. The real screenshot sample has not been dumped at all.
- Sample comparison of A/B/C: **`NOT DONE YET`**.

**Observability gap:** the dump preamble does not record the app version, so it is impossible to tell
from a dumped text which build produced it. Worth adding to `filePreamble` in the next build.

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

## Build constraints (each one paid for with a failed CI run)

The Makefile compiles all sources in one `clang` invocation and links only
`-framework UIKit -framework Foundation -lsqlite3`. It is not to be changed to work around code
that could be written differently.

- **No member in an Objective-C method family unless it really returns an owned object.**
  `@property(nonatomic, strong) UIButton *copyButton;` is a hard **error** under ARC
  (`property follows Cocoa naming convention for returning 'owned' objects`), and so is a method
  like `- (void)copyReport:(id)sender`. Use a neutral name: `clipboardButton`, `putInClipboard:`.
  This broke CI run `35715292572`.
- **`CGRectZero` / `CGSizeZero` / `CGPointZero` / `CGAffineTransformIdentity` are CoreGraphics
  symbols**, and CoreGraphics is not linked. Use the inline `CGRectMake(0, 0, 0, 0)` instead.
  This broke CI run `35715609657` at link time (`Undefined symbols: "_CGRectZero"`).
- CI run `35715762990` is the first green Phase 2 UI build: zero warnings.

Cheap local pre-flight checks before pushing (no Objective-C toolchain is available here):

- brace/bracket balance check per file
- `grep` for properties or methods starting with `alloc` / `new` / `copy` / `init` / `mutableCopy`
- `grep` for `CGRectZero`-style CoreGraphics constants

## Pushing when the local proxy blocks github.com

Observed on 2026-09-22: `git push` failed with `CONNECT tunnel failed, response 502` for
`github.com`, while `api.github.com` kept working (the proxy at `127.0.0.1:18513` allows the API
host and refuses the git host). `tools/api_push.py` rebuilds the current local commit through the
Git Data API and verifies, before moving any ref, that the uploaded blobs, the tree **and the
commit object** are byte-identical to the local ones — so local and remote never diverge. It
aborts without touching a ref if anything differs.


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

**Conclusion (what the evidence supports):** a text field was in use and the keyboard was loading. The
first time this process renders a CoreUI "styled image" it creates the process-wide shared
`CIContext`, and that construction segfaults on this device/OS. Our own code never appears in the
stack, and the entitlements are not implicated: the same process had already read `Photos.sqlite`
successfully.

**How wide is the trigger?** The captured stack enters through `UITextSelectionInteraction
_handleMultiTapGesture:` — a **multi-tap inside a text field** (for example a double tap to select a
word), which is what activates the field and loads the keyboard. Whether a plain single tap followed
by typing is also enough **was not established**; the 0.2.0 exports that exist were produced through
a text field, so typing itself was evidently possible at least once. Treat "showing the keyboard"
as the mechanism on the crash path, and "multi-tap in a text field" as the confirmed trigger.

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

## Phase 2 — first comparison attempt (2026-09-22, evening)

Evidence: `logs/detail_heif_converted.txt` and `logs/detail_png_original.txt`, analysed with
`tools/diff_dumps.py` and `tools/dump_view.py`.

### The pair of exports does not contain the comparison that was intended

| file | search term | matches | what was dumped in full |
| --- | --- | --- | --- |
| `detail_heif_converted.txt` | `5691` | 1 | Z_PK 5691 `IMG_5701.HEIC` ✔ |
| `detail_png_original.txt` | **`5`** | 20 | the first 5, and those 5 are **HEIC** (`IMG_5697`…`IMG_5701`) |

The term `5` matched every file name containing a `5`, and because the list is ordered by
`Z_PK DESC` the five fully dumped assets are the newest HEICs. The PNG assets
(`IMG_5696.PNG`, `IMG_5695.PNG`, `IMG_5694.PNG`, `IMG_5693.PNG`) appear **only as one-line
headers, with no field data at all**.

**Therefore the intended PNG ↔ HEIC field comparison has not been performed yet.** It needs a
re-export of the PNG asset. This is a repeat of the failure mode that motivated removing the text
field: a search term that silently matches something else.

### Findings that the files DO support

1. **Determinism control.** The same asset (5691) was dumped into both files. Of ~280 fields only
   two differ: `ZADDITIONALASSETATTRIBUTES.Z_OPT` 5 → 7 and `ZPENDINGVIEWCOUNT` 2 → 4. The
   difference is the database changing (the photo was viewed between the two dumps), not the dump
   being unstable.
2. **The five new HEICs are one batch from a third-party importer.** All five carry
   `ZIMPORTEDBYBUNDLEIDENTIFIER = com.example.PNG2HEIF`, `ZIMPORTEDBYDISPLAYNAME = PNG2HEIF`,
   `ZIMPORTEDBY = 3`, `ZDATECREATEDSOURCE = 3`, all are 1242 × 2208 in `DCIM/105APPLE`, and four of
   the five are in the trash (`ZTRASHEDSTATE = 1`); only `IMG_5701.HEIC` is live.
3. **`ZORIGINALHASH` is a placeholder, not a digest.** All five files, whose sizes differ
   (23 800 … 182 684 bytes), carry the identical 8-byte blob `66616b6568617368` = ASCII
   `fakehash`. A real hash of five different files cannot be equal, so this value was written by the
   importer or by the test setup. **Any conclusion that relies on `ZORIGINALHASH` is void until this
   is explained.**
4. **No camera/lens data and no "screenshot" string anywhere.** In the full 2862-line dump every
   EXIF-derived field is NULL — `ZCAMERAMAKE`, `ZCAMERAMODEL`, `ZLENSMODEL`, `ZISO`, `ZAPERTURE`,
   `ZSHUTTERSPEED`, `ZFOCALLENGTH`, `ZFOCALLENGTHIN35MM`, `ZWHITEBALANCE`, `ZMETERINGMODE`,
   `ZDIGITALZOOMRATIO`, `ZEXPOSUREBIAS`, `ZCODEC`, `ZLATITUDE`, `ZLONGITUDE` — and the only
   non-NULL one is `ZFLASHFIRED = 0`. No field value contains `screen` / `screenshot`.
   So an imported asset that has **no camera information at all** is still not a screenshot: absence
   of lens data cannot be the rule. A screenshot would have to be a *positive* declaration, which is
   the user's hypothesis — and it is still untested.
5. **`ZKINDSUBTYPE` is not the file extension.** On the same device an older HEIC
   (`IMG_5690.HEIC`, Z_PK 5681, from the first `Asset list`) sits in `ZKINDSUBTYPE = 2`, while these
   five **HEIC** files sit in `ZKINDSUBTYPE = 0` — the same group as `IMG_5684.JPG`. Candidate
   explanations to test, not conclusions: the importer may write the asset record itself (see the
   fake hash), or the value follows the coded codec inside the container rather than the container.
6. `ZINTERNALRESOURCE.ZQUALITYSORTVALUE` is `2147418120` (= `0x7FFFC008`, a NaN float bit pattern)
   for all five. Recorded only because it is identical for five different files; unaffected by any
   conclusion yet.

### What this means for the hypothesis

The hypothesis under test is *"iPhone writes 'this is a screenshot' into the lens information, and
that is why Photos accepts it as a screenshot"*. Nothing in these two exports can support or refute
it, because neither export contains a real screenshot, and the "PNG" export contains no PNG data.
What the exports do establish is the shape of the search space: for these imported assets the only
classification-shaped columns are `ZKIND` / `ZKINDSUBTYPE` / `ZSAVEDASSETTYPE` (all constant
`0 / 0 / 3` for the batch) plus the EXIF-derived fields — and the EXIF-derived fields are empty.


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
- that `ZKINDSUBTYPE` follows the coded codec rather than the container (see finding 5 above)
- that the PNG2HEIF importer goes through the Photos framework rather than writing rows itself
  (its assets carry `ZIMPORTEDBY = PNG2HEIF` and a `fakehash` placeholder, so this has to be
  answered before those assets are used as evidence)
- that the screenshot classification is written into the file's camera/lens metadata (the user's
  working hypothesis; **no sample that can test it has been dumped yet**)

Do not turn any of these into project facts without device evidence.

## Next experiment

1. **Re-export the PNG asset properly.** The previous export searched `5` and only dumped HEICs.
   In `Assets`, tap the row of the source PNG → `Detail` → `Share`, or select it together with the
   HEIC and use `Compare` (no typing). Only then is the PNG ↔ HEIC field diff actually performed.
2. **Dump a real native screenshot** (power + volume up). This is the only sample that can test the
   camera/lens hypothesis; nothing dumped so far contains a screenshot.
3. **Dump a control HEIC imported by another route** (`IMG_5690.HEIC`, Z_PK 5681, `ZKINDSUBTYPE=2`)
   and compare it with `IMG_5701.HEIC` (`ZKINDSUBTYPE=0`) to test finding 5.
4. In the Photos UI, record for every sample whether it appears under **Screenshots**. That is the
   ground truth for the classification and it costs nothing.
5. Answer how PNG2HEIF imports (Photos framework or direct database write). If it writes rows
   itself, its assets say nothing about Photos' own classification logic.
6. Keep the dumps out of the trash and out of the moment/highlight comparisons: four of the five
   HEICs in this batch are trashed, which perturbs `ZTRASHEDSTATE`, `ZTRASHEDDATE`, `ZMOMENT` and
   the `ZHIGHLIGHTBEING*` columns.

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
