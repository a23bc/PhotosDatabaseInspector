# Photos Database Inspector — Handover

## Status

**Phase 2 — asset record inspection works on device; the 0.2.0 UI had to be replaced because it crashed.**

- Phase 1 (schema discovery): `DONE`, verified by a real device scan.
- Phase 2 (asset record dump + comparison): `WORKS` (0.2.0 produced a full asset list on the device).
- Phase 2 UI with text input: **`RETRACTED`** — see "Crash" below.
- Phase 2 UI without text input (0.2.1): `BUILDS GREEN` (CI run `35715762990`, zero compiler
  warnings, artifact `build/ci/PhotosDatabaseInspector-0.2.1.tipa`).
- Asset lookup: **`BROKEN in 0.2.0 and 0.2.1`** — selecting an old asset dumped the newest five
  (see the regression section). Fixed in **0.2.2**, pinned by `tools/repro_search_bug.py`, and
  **confirmed on the device**: the 19:07 compare shows `exact Z_PK = 5691` and `exact Z_PK = 5`
  resolving to exactly the two selected rows.
- Second sample comparison: `DONE, BUT CONFOUNDED` — screenshot-side PNG vs its HEIC conversion.
- Third sample comparison: `DONE, AGE-MATCHED`. 42 differing fields instead of 331. Leaves exactly
  one candidate (`ZKINDSUBTYPE` 10 vs 0) that still carries an unresolved confound, retracts the
  `ZORIGINALHASH` reading, and identifies the missing positive control.
- Sample comparison of A/B/C: **`DONE for the DB side; needs a camera-photo control`**.

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

## Regression: 0.2.1 dumped the newest five photos whatever was selected (fixed in 0.2.2)

Reported from the device: *"no matter which photo I select it dumps the newest five, and comparing an
old PNG with a new HEIC compared the newest two photos."* Correct, and it was a design error, not a
typo.

**Cause.** 0.2.1 resolved an asset with one OR-ed query:

```sql
SELECT * FROM "ZASSET" WHERE (ZUUID = ? OR ZUUID LIKE '%?%' OR ZFILENAME LIKE '%?%' OR Z_PK = ?
                            OR Z_PK IN (SELECT ZASSET FROM "ZADDITIONALASSETATTRIBUTES" WHERE ZORIGINALFILENAME LIKE '%?%'))
ORDER BY Z_PK DESC LIMIT 20
```

Selecting the old asset `Z_PK=5` therefore also matched every file name containing a `5`. With
`ORDER BY Z_PK DESC LIMIT 20` the newest 20 fragment hits filled the result set, the requested row
fell outside it, and the dump printed the newest five — `assets[0]` in `Compare` did the same, which
is why two selected samples became "the newest two photos". The report printed the SQL, but the
`matches` count and the identity of the first match were not printed, so the mis-resolution was
invisible in the exported text.

**Reproduced and pinned locally** by `tools/repro_search_bug.py`, which builds a miniature ZASSET,
runs the exact SQL copied out of the dump, shows that `Z_PK=5` is not even in the 20 results, and
then asserts the new resolution rules. It needs no iOS toolchain:

```text
legacy first five = [5699, 5698, 5697, 5696, 5695]      <-- selected Z_PK=5 is missing
```

**Fix (0.2.2).** Resolution is a list of attempts, most precise first, and the first attempt that
produces rows wins:

| term | attempts |
| --- | --- |
| digits only | `Z_PK = ?1` (integer bind) — exact, and a `LIMIT` cannot hide it |
| anything else | `ZUUID = ?1 COLLATE NOCASE` / `ZFILENAME = ?1 COLLATE NOCASE`, then a fragment fallback over `ZUUID` / `ZFILENAME` / `ZORIGINALFILENAME` |
| empty | newest asset |

Plus three changes that make a wrong pick visible instead of silent:

- `AssetListViewController` passes the selected row's `Z_PK` as a number through the new
  `-assetDumpReportForPrimaryKey:` / `-assetCompareReportForPrimaryKeys:` entry points, so the
  identity is never round-tripped through a string search
- the SEARCH block now prints `lookup : <which attempt matched> (attempt n/m)` and
  `first match: Z_PK=… ZFILENAME=… ZUUID=…`, and prints a `WARNING` if a numeric term resolved to a
  different row
- `Compare` prints `WARNING` when two terms resolve to the same asset, because that diff is empty
  by construction and would otherwise look like "no difference found"

Verified locally by the same regression test (exact primary key, case-insensitive exact file name /
UUID, fragment fallback newest-first, empty term, and the case where a file name merely *contains*
the digits: `IMG_0005_COPY.PNG` must not match the term `5`).


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

This is the same defect as the 0.2.1 lookup bug described above — `term : 5` with the newest five
dumped is exactly its signature — so the PNG never had a chance to appear. 0.2.2 fixes it and prints
which lookup matched plus the identity of the first match, so the next export can be checked at a
glance. **The intended PNG ↔ HEIC field comparison still has not been performed.**

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


## Second comparison attempt: screenshot-side PNG vs its HEIC conversion (2026-09-22 19:07)

Evidence: the `ASSET COMPARE` export pasted by the user, generated `2026-09-22T11:03:42Z`.

**The report proves 0.2.2 is on the device and the selection fix works**: the SEARCHES lines carry
`-> exact Z_PK = …`, which only 0.2.2 prints, and each term resolved to exactly the row the user
picked instead of to a fragment set.

```text
  A: 5691  -> exact Z_PK = 5691  Z_PK=5691  ZFILENAME=IMG_5701.HEIC  public.heic
  B: 5     -> exact Z_PK = 5     Z_PK=5     ZFILENAME=IMG_0005.PNG   public.png
fields compared : 536   identical 205   differing 331
```

### Three confounds, all at once

The pair differs in age, in container format, **and** in screenshot-ness, so no single difference can
be attributed to any one of them.

1. **Age / processing state — the dominant one.** B is 14 months old (`ZADDEDDATE` 2025-07-12),
   A is minutes old (2026-09-22T10:28). Entire tables exist for B and not for A:
   `ZMEDIAANALYSISASSETATTRIBUTES`, `ZCOMPUTEDASSETATTRIBUTES`, `ZDETECTEDFACE` (2 rows),
   `ZPERSON` (2 rows), `ZSCENEPRINT`, `ZCHARACTERRECOGNITIONATTRIBUTES`. A's own values are the
   "not computed yet" defaults: `ZCURATIONSCORE` 0 (B 0.25), `ZOVERALLAESTHETICSCORE` 0.5
   (B 0.112488), and A's to-one keys `ZCOMPUTEDATTRIBUTES` / `ZMEDIAANALYSISATTRIBUTES` are null
   while B's point at row 5. Bookkeeping agrees: `Z_OPT` 2 vs 62, `ZVIEWCOUNT` 0 vs 4,
   `ZSHARECOUNT` 0 vs 1. **Most of the 331 differing fields are this**, not a classification.
2. **Format.** `public.heic` vs `public.png`; `ZINTERNALRESOURCE.ZCOMPACTUTI` 3 vs 6;
   `ZDATASTOREKEYDATA` `…c001` vs `…4003`; `ZQUALITYSORTVALUE` `…120` vs `…122`.
3. **Screenshot or not.** B was written by `com.apple.springboard` / `SpringBoard`
   (A: `com.example.PNG2HEIF`), it is a PNG in `DCIM/100APPLE`, and its date is from 2025-07-12.
   That is the signature of a native screenshot. Not proven from the database alone — the
   Screenshots album in the UI settles it in seconds, as does dumping a freshly taken screenshot.

### What survives all three confounds — and what it says about the lens hypothesis

`ZEXTENDEDATTRIBUTES` appears in the diff list **only** as `Z_PK` and `ZASSET`. Every EXIF-derived
column is therefore *identical* between the two assets, and the earlier 0.2.1 dump shows those
columns are all **NULL** for A, with `ZFLASHFIRED = 0` the only value present. So the
SpringBoard-imported PNG has **no camera or lens information either**.

⇒ The database holds no "this is a screenshot" note inside the camera/lens fields, because those
fields are empty on both sides of the comparison. If a declaration exists at all it lives in the
**file** (PNG chunks / EXIF), and Photos would have to *derive* the classification from it. That is a
file-level question the database cannot answer, and it is a separate experiment: copy
`IMG_0005.PNG` (and `IMG_5701.HEIC`) off the device and read the actual bytes.

Also identical, and therefore not the discriminator: `ZKIND` 0/0, `ZSAVEDASSETTYPE` 3/3,
`ZDEPTHTYPE`, `ZHDRTYPE`, `ZORIENTATION`, `ZWIDTH`/`ZHEIGHT` (1242 × 2208 on both sides),
`ZADDITIONALASSETATTRIBUTES.ZORIGINALWIDTH`/`HEIGHT`/`ORIENTATION`, `ZLATITUDE`/`ZLONGITUDE`,
`ZGPSHORIZONTALACCURACY`, `ZFLASHFIRED`. Matching dimensions and orientation on both sides is
consistent with A having been produced from B.

### The remaining candidate fields, and the confound each one cannot escape

| field | A (HEIC, converted) | B (PNG, SpringBoard) | reading |
| --- | --- | --- | --- |
| `ZASSET.ZKINDSUBTYPE` | 0 | 10 | 10 may just mean "PNG"; this pair changes format and classification together, so it cannot tell them apart |
| `ZADDITIONALASSETATTRIBUTES.ZCLOUDKINDSUBTYPE` | 0 | 3 | mirrors the same idea |
| `ZADDITIONALASSETATTRIBUTES.ZDATECREATEDSOURCE` | 3 | 1 | co-varies with `ZEXIFTIMESTAMPSTRING` in all six assets we have (EXIF present → 1, EXIF null → 3), so it most likely records **where the creation date came from**, not the classification |
| `ZADDITIONALASSETATTRIBUTES.ZIMPORTEDBY*` | PNG2HEIF | com.apple.springboard / SpringBoard | provenance of the import, not a classification flag |
| `ZADDITIONALASSETATTRIBUTES.ZEXIFTIMESTAMPSTRING` | null | 2025:07:12 16:43:46 | file metadata |
| `ZASSET.ZFACEAREAPOINTS` | −100 | 12385040713580639 | pipeline state: B has faces, A has not been analysed |

`ZSCREENTIMEDEVICEIMAGESENSITIVITY` is `-1` in B's row. `-1` reads as "not computed" rather than
"true", and it stays on the "not evidence" list.

### Next experiments that remove the confounds

1. **Age-matched pair.** Take a fresh screenshot now and import a fresh copy of something else now,
   then dump both immediately. Neither has analysis rows yet, so any difference cannot be pipeline
   state.
2. **Format held constant.** Dump a **non-screenshot PNG** (import one through Files or AirDrop).
   If it is also `ZKINDSUBTYPE = 10` then 10 means PNG and the flag is elsewhere; if it is 0 then 10
   starts to look like the screenshot marker.
3. **Classification held constant, format varied.** That is this comparison, and it produced only
   format/provenance differences — which is itself a datum: converting the PNG to HEIC moved
   `ZKINDSUBTYPE` from 10 to 0.
4. **File level.** Copy `IMG_0005.PNG` off the device. The database stores no screenshot marker for
   it, so if the hypothesis is about the file's camera/lens metadata, the file is the only place it
   can be checked.

### Product improvement this report argues for (not shipped)

The Compare report should split the differing fields into "both sides have a value and they differ"
and "the row does not exist on one side". Most of these 331 lines are the second kind — the analysis
pipeline simply has not run on the fresh asset — and separating them would shrink the report to the
few lines that matter. A warning when the two assets' `ZADDEDDATE` differ by more than a few minutes
would flag the age confound automatically.


## Third comparison: age-matched, three samples (2026-09-22 19:18)

Evidence: the asset dump of Z_PK 5696 and the `ASSET COMPARE` of 5696 / 5693 / 5684.

### The age confound is gone, and the noise dropped 8×

| | A = 5696 | B = 5693 | C = 5684 |
| --- | --- | --- | --- |
| file | IMG_5706.PNG | IMG_5703.HEIC | IMG_5694.PNG |
| imported by | `com.heytap.oshare-export` (O+互联) | `com.example.PNG2HEIF` | **`com.apple.springboard` (SpringBoard)** |
| added (UTC) | 11:17:13 | 11:14:49 | 10:13:43 |
| container | public.png, sRGB | public.heic, Display P3 | public.png, Display P3 |
| pixels | 1080 × 2338 | 1242 × 2208 | 1242 × 2208 |
| original file name | `comment_<hash>.png` | IMG_5703.HEIC | IMG_5694.PNG |
| **`ZKINDSUBTYPE`** | **0** | **0** | **10** |
| `ZKIND` / `ZSAVEDASSETTYPE` | 0 / 3 | 0 / 3 | 0 / 3 |
| `ZDATECREATEDSOURCE` | 3 | 3 | **1** |
| `ZEXIFTIMESTAMPSTRING` | (null) | (null) | **2026:09:22 18:13:40** |
| `ZINTERNALRESOURCE.ZCOMPACTUTI` | 6 | 3 | 6 |
| `ZDATASTOREKEYDATA` | `…4003` | `…c001` | `…4003` |
| `ZQUALITYSORTVALUE` | `…122` | `…120` | `…122` |
| camera / lens block | all NULL | all NULL | all NULL |

- 42 fields differ out of 280, 238 identical — against 331 of 536 for the previous, age-confounded
  pair. Same-day assets are the right instrument; 14 months apart is not.
- The whole `ZEXTENDEDATTRIBUTES` block again appears in the diff only as `Z_PK` / `ZASSET`, so the
  **SpringBoard-imported PNG has no camera or lens information either**. Third sample, same result.

### The only non-identity difference that could be the classification

A and C are **both PNG, imported an hour apart, both `ZCOMPACTUTI` 6**. What separates them:

- C is the SpringBoard import (a screenshot); A is an app import from O+互联
- C carries a file creation timestamp (`ZEXIFTIMESTAMPSTRING`), A does not — hence
  `ZDATECREATEDSOURCE` 1 vs 3

`ZKINDSUBTYPE` is 10 for C and 0 for A, so it **does not encode the container** (two PNGs, two
values). But this pair changes *screenshot-ness and timestamp presence together*, so it still cannot
say which of them sets the field. Both readings stay open:

- **H1, "10 = screenshot"**: C is SpringBoard's screenshot, and `Z_PK 5` — also a SpringBoard PNG,
  from 2025-07-12 — is 10 as well.
- **H2, "10 = the original file carried a creation timestamp"**: 10 co-varies with
  `ZEXIFTIMESTAMPSTRING` and with `ZDATECREATEDSOURCE` 1-vs-3 across every sample that has both.

### Retraction: `ZORIGINALHASH` is a device-wide placeholder, not an importer artefact

This dump shows `ZORIGINALHASH = (blob 8 bytes) 66616b6568617368` = ASCII **`fakehash`** for an asset
imported by a *different* app (`com.heytap.oshare-export`). Combined with `ZORIGINALHASH` never
appearing in any of the three comparisons, the same value is on **every asset we have looked at**:
9+ assets, 3 unrelated importers, 14 months — including the year-old `Z_PK 5`.

The earlier reading *"the importer wrote a placeholder"* is **RETRACTED**. It is not the importer
(two unrelated importers cannot agree byte for byte) and it is not "not computed yet" (the year-old
asset has it too). Something on this device writes `fakehash` into every asset, which points at a
patched Photos import path or a jailbreak tweak. **Until that is explained this column is void — and
a patched import path could be writing other columns too, which would put every conclusion drawn
from this device in doubt.** By contrast `ZMASTERFINGERPRINT` / `ZFINGERPRINT` behave the way a
pipeline does: null on today's assets, a real base64 SHA-1 on the year-old `Z_PK 5`.

### Missing control: the camera columns have never been seen populated

Every asset dumped so far has an empty camera/lens block, which makes "empty" a weak observation —
we do not know that this device's Photos ever fills them. **Before drawing anything from the
emptiness, dump one photograph taken with the camera** (`ZKINDSUBTYPE` 2 per the census) and check
whether `ZCAMERAMAKE` / `ZCAMERAMODEL` / `ZLENSMODEL` / `ZISO` / `ZAPERTURE` carry values.

### Next experiments, in the order that decides the most

1. **Positive control on the camera columns.** Dump a camera photo. If its camera fields are
   populated, the emptiness for screenshots becomes meaningful; if it is empty too, the whole
   lens-metadata branch is moot on this device.
2. **Same screenshot file, two import paths.** Take a screenshot (SpringBoard, expect 10), then get
   that same PNG into Photos through Files / AirDrop. If the second copy is also 10, the marker
   travels with the file; if it is 0, SpringBoard's import path declared it. This is the direct test
   of "the file declares itself a screenshot".
3. **A non-screenshot PNG carrying a creation timestamp.** If it lands on 10, then
   `ZKINDSUBTYPE = 10` means "the file carried a timestamp", not "screenshot".
4. **Find out what writes `fakehash`** — tweak inventory, or search the jailbreak file system for
   the string.

### Product improvement (still not shipped)

Unchanged: split the report into "values differ" versus "row missing on one side", and warn when the
two assets' `ZADDEDDATE` differ by more than a few minutes. The age-matched run shows how much noise
that would have removed automatically.


## Things NOT established yet

The following are hypotheses, not findings:

- that a field named `ZSCREENTYPE` exists on iOS 15 (the scan found none)
- that `ZSCREENTIMEDEVICEIMAGESENSITIVITY` has anything to do with screenshots (`-1`, "not computed")
- that `ZKINDSUBTYPE=10` means "screenshot" rather than "the original file carried a creation
  timestamp"; the age-matched pair cannot separate the two
- that `ZADDITIONALASSETATTRIBUTES.ZDATECREATEDSOURCE` is a classification (it tracks where the
  creation date came from: file metadata 1, import time 3 — consistent across every sample so far)
- that one field alone controls the Screenshot classification
- that the classification lives in `ZASSET` or in `ZADDITIONALASSETATTRIBUTES`
- that modifying Photos.sqlite would survive Photos daemon reconciliation
- that a read-only SQLite connection sees the contents of the present `-wal` file
- that the keyboard is the only way to trigger the CoreImage crash
- that `ZKINDSUBTYPE` follows the coded codec rather than the container
- that the PNG2HEIF importer goes through the Photos framework rather than writing rows itself
- that `IMG_0005.PNG` / `IMG_5694.PNG` really are native screenshots (a SpringBoard import is strong
  evidence, not proof)
- that the screenshot classification is written into the file's camera/lens metadata (the user's
  hypothesis). The database side is answered for three samples — a SpringBoard-imported PNG has
  every camera/lens column empty, exactly like an ordinary import — but **we still lack a positive
  control showing that this device fills those columns at all**
- that the camera/lens columns are ever populated on this device (no camera photo has been dumped)
- that this device's Photos import path is unpatched. Every asset carries the identical
  `ZORIGINALHASH = "fakehash"`, which no stock Photos behaviour explains

Do not turn any of these into project facts without device evidence.

## Next experiment

1. **Positive control on the camera columns.** Dump one photograph taken with the camera
   (`ZKINDSUBTYPE = 2` per the census) and check whether `ZCAMERAMAKE` / `ZCAMERAMODEL` /
   `ZLENSMODEL` / `ZISO` / `ZAPERTURE` carry values. Without this, "the camera block is empty" says
   nothing, because no sample has ever shown it populated.
2. **Same screenshot file, two import paths.** Screenshot it (SpringBoard → expect `ZKINDSUBTYPE`
   10), then get that same PNG into Photos through Files / AirDrop. Copied in as 10 ⇒ the marker
   travels with the file; copied in as 0 ⇒ SpringBoard's import path declared it.
3. **A non-screenshot PNG that carries a creation timestamp.** If it lands on 10, then
   `ZKINDSUBTYPE = 10` means "the file carried a timestamp", not "screenshot".
4. **Explain `fakehash`.** Tweak inventory, or search the jailbreak file system for the string.
   Until then, treat every conclusion from this device as provisional.
5. Keep comparing assets **added within the same hour**. The age-matched run cut the diff from 331
   fields to 42; the older comparison was mostly measuring the analysis pipeline.
6. In the Photos UI, record for every sample whether it appears under **Screenshots** — the ground
   truth for the classification, and it costs nothing.
7. Answer how PNG2HEIF and O+互联 import (Photos framework or direct database write).
8. Keep samples out of the trash and out of moment/highlight comparisons: four of the five HEICs in
   the PNG2HEIF batch are trashed, which perturbs `ZTRASHEDSTATE`, `ZTRASHEDDATE`, `ZMOMENT` and the
   `ZHIGHLIGHTBEING*` columns.

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
