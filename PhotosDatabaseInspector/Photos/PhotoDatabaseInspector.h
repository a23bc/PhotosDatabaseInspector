#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*
 * Read-only inspector for a Photos SQLite database.
 *
 * Phase 1 (inspectReport) reads schema only.
 * Phase 2 (the asset* methods) reads real ZASSET rows and the tables that reference them.
 *
 * No method in this class performs INSERT / UPDATE / DELETE / DDL,
 * sets journal_mode, or runs a WAL checkpoint. Everything is opened
 * with SQLITE_OPEN_READONLY.
 */
@interface PhotoDatabaseInspector : NSObject
- (instancetype)initWithDatabasePath:(NSString *)path;

/* Phase 1: schema report (sqlite_master objects, PRAGMA table_info, name heuristic). */
- (NSString *)inspectReport;

/* Phase 2: the newest `limit` ZASSET rows plus a grouped ZKIND/ZKINDSUBTYPE/ZSAVEDASSETTYPE census. */
- (NSString *)assetListReportWithLimit:(NSInteger)limit;

/* Phase 2: the grouped census on its own. */
- (NSString *)assetCensusReport;

/* Phase 2: structured asset list for a UI (keys: total, count, rows).
   Each row is keyed by the ZASSET column name, so a UI can pick samples by tapping. */
- (NSDictionary<NSString *, id> *)assetOverviewWithLimit:(NSInteger)limit;

/* Phase 2: full record dump for one asset, addressed by ZASSET.Z_PK. */
- (NSString *)assetDumpReportForPrimaryKey:(long long)pk;

/* Phase 2: full record dump (ZASSET + every table referencing this asset) for each match.
   `search` may be a Z_PK, a ZUUID, a file name fragment or an original file name fragment.
   Pass nil/empty to dump the most recent asset. At most 5 assets are dumped in full.

   Resolution order, and it matters: a term made only of digits is an **exact Z_PK** and nothing
   else; otherwise an exact ZUUID / file name is tried first and a fragment match is only a
   fallback. A lookup never mixes an exact key with fragments, because a fragment match set plus
   "ORDER BY Z_PK DESC LIMIT n" silently drops the row that was asked for. */
- (NSString *)assetDumpReportForSearch:(nullable NSString *)search;

/* Phase 2: field-by-field comparison of assets addressed by ZASSET.Z_PK. */
- (NSString *)assetCompareReportForPrimaryKeys:(NSArray<NSNumber *> *)pks;

/* Phase 2: field-by-field comparison of the first asset matched by each search term.
   Same resolution rules as above. The union of all fields is compared; differing fields are
   listed per term. */
- (NSString *)assetCompareReportForSearches:(NSArray<NSString *> *)searches;

#pragma mark TEMPORARY — experiment only, the one write path in this project

/* Added on request on 2026-09-22 to test whether ZASSET.ZKINDSUBTYPE decides how Photos
   classifies an asset. It opens the database SQLITE_OPEN_READWRITE and runs exactly one UPDATE
   on exactly one row. No DDL, no journal_mode change, no checkpoint, no VACUUM, and Z_OPT is
   deliberately left alone. Pass dryRun:YES for the same report with no write at all.

   Returned keys: dryRun, error, filename, uti, savedAssetType, before, after, opt, changed.
   Remove this API together with its button before any release. */
- (NSDictionary<NSString *, id> *)kindSubtypeChangeForAssetPrimaryKey:(long long)pk
                                                              toValue:(long long)subtype
                                                               dryRun:(BOOL)dryRun;
- (NSString *)reportForKindSubtypeChange:(NSDictionary<NSString *, id> *)change;
@end

NS_ASSUME_NONNULL_END
