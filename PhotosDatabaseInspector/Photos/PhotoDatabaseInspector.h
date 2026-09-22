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

/* Phase 2: full record dump (ZASSET + every table referencing this asset) for each match.
   `search` may be a Z_PK, a ZUUID, a file name fragment or an original file name fragment.
   Pass nil/empty to dump the most recent asset. At most 5 assets are dumped in full. */
- (NSString *)assetDumpReportForSearch:(nullable NSString *)search;

/* Phase 2: field-by-field comparison of the first asset matched by each search term.
   The union of all fields is compared; differing fields are listed per term. */
- (NSString *)assetCompareReportForSearches:(NSArray<NSString *> *)searches;
@end

NS_ASSUME_NONNULL_END
