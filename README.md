# PhotosDatabaseInspector

A small **read-only** iOS 15+ TrollStore utility for inspecting the SQLite databases under `/var/mobile/Media/PhotoData/`.

The project is intentionally independent from the larger `iOSCleanerInspector` app. It is an experiment tool for determining what Photos stores about assets, especially the differences between a native Screenshot asset and an ordinary imported image.

## Current scope

Phase 1 only:

- recursively locate `.sqlite` / `.sqlite3` databases below `PhotoData`
- report matching `-wal` / `-shm` sidecars
- open each database with SQLite read-only mode
- enumerate `sqlite_master`
- enumerate every table with `PRAGMA table_info`
- flag column names that may be related to screenshots/media/import/capture
- export the raw report through the iOS share sheet

**No database write operation is implemented.** There is no INSERT, UPDATE, DELETE, schema change, checkpoint, or vacuum operation.

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

## Important experimental rule

Do not interpret a column name such as `ZSCREENTYPE` as proof that it is the Screenshot flag. Phase 1 only discovers schema. The next phase must compare real assets on an iOS 15 device.
