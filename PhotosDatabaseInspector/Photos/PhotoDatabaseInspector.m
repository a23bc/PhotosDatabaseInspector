#import "PhotoDatabaseInspector.h"
#import <sqlite3.h>

#pragma mark - Text helpers

static NSString *S(const unsigned char *v) {
    if (!v) return @"NULL";
    NSString *s = [NSString stringWithUTF8String:(const char *)v];
    return s ?: @"(invalid utf8)";
}

/* Single-quoted SQL literal escaping (used for identifiers in PRAGMA statements). */
static NSString *Q(NSString *identifier) {
    return [identifier stringByReplacingOccurrencesOfString:@"'" withString:@"''"];
}

/* Double-quoted SQL identifier. */
static NSString *QID(NSString *identifier) {
    return [NSString stringWithFormat:@"\"%@\"", [identifier stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""]];
}

/* Escape LIKE wildcards so that a user-supplied search term is matched literally.
   Pairs with "... LIKE ? ESCAPE '\'". */
static NSString *LikeEscape(NSString *s) {
    NSMutableString *m = [s mutableCopy];
    [m replaceOccurrencesOfString:@"\\" withString:@"\\\\" options:0 range:NSMakeRange(0, m.length)];
    [m replaceOccurrencesOfString:@"%" withString:@"\\%" options:0 range:NSMakeRange(0, m.length)];
    [m replaceOccurrencesOfString:@"_" withString:@"\\_" options:0 range:NSMakeRange(0, m.length)];
    return m;
}

/* Keep a value on one line so that reports stay grep- and diff-friendly. */
static NSString *Flat(NSString *s) {
    NSMutableString *m = [s mutableCopy];
    [m replaceOccurrencesOfString:@"\\" withString:@"\\\\" options:0 range:NSMakeRange(0, m.length)];
    [m replaceOccurrencesOfString:@"\n" withString:@"\\n" options:0 range:NSMakeRange(0, m.length)];
    [m replaceOccurrencesOfString:@"\r" withString:@"\\r" options:0 range:NSMakeRange(0, m.length)];
    [m replaceOccurrencesOfString:@"\t" withString:@"\\t" options:0 range:NSMakeRange(0, m.length)];
    return m;
}

static NSString *Clip(NSString *s, NSUInteger max) {
    if (s.length <= max) return s;
    return [NSString stringWithFormat:@"%@...<truncated, total=%lu chars>", [s substringToIndex:max], (unsigned long)s.length];
}

static NSString *Pad(NSString *s, NSUInteger width) {
    if (s.length >= width) return s;
    return [s stringByPaddingToLength:width withString:@" " startingAtIndex:0];
}

static BOOL IsDigits(NSString *s) {
    if (!s.length) return NO;
    for (NSUInteger i = 0; i < s.length; i++) {
        unichar c = [s characterAtIndex:i];
        if (c < '0' || c > '9') return NO;
    }
    return YES;
}

/* Blobs are a real part of this investigation (ZORIGINALHASH, ZFACEREGIONS, ...),
   so they are shown as a hex prefix plus their true length. */
static NSString *BlobText(const void *bytes, int len) {
    const unsigned char *b = (const unsigned char *)bytes;
    if (!b || len <= 0) return [NSString stringWithFormat:@"(blob, %d bytes)", len];
    int shown = len > 64 ? 64 : len;
    NSMutableString *hex = [NSMutableString stringWithCapacity:(NSUInteger)(shown * 2 + 24)];
    for (int i = 0; i < shown; i++) [hex appendFormat:@"%02x", b[i]];
    if (len > shown) [hex appendFormat:@"...<+%d bytes>", len - shown];
    return [NSString stringWithFormat:@"(blob %d bytes) %@", len, hex];
}

/* Core Data stores dates as seconds since 2001-01-01T00:00:00Z. 0 means "unset". */
static NSString *CDDate(double ts) {
    if (ts == 0.0) return @"unset (Core Data epoch)";
    static NSDateFormatter *fmt;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        fmt = [NSDateFormatter new];
        fmt.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        fmt.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
        fmt.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'";
    });
    return [fmt stringFromDate:[NSDate dateWithTimeIntervalSinceReferenceDate:ts]];
}

static NSString *UTCTimestamp(void) {
    NSDateFormatter *f = [NSDateFormatter new];
    f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    f.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    f.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
    return [f stringFromDate:[NSDate date]];
}

/* One column of the current row, formatted for a report. */
static NSString *ValueText(sqlite3_stmt *st, int idx) {
    const char *dt = sqlite3_column_decltype(st, idx);
    NSString *decl = dt ? [[NSString stringWithUTF8String:dt] uppercaseString] : @"";
    switch (sqlite3_column_type(st, idx)) {
        case SQLITE_NULL:
            return @"(null)";
        case SQLITE_INTEGER:
            return [NSString stringWithFormat:@"%lld", sqlite3_column_int64(st, idx)];
        case SQLITE_FLOAT: {
            double v = sqlite3_column_double(st, idx);
            if ([decl isEqualToString:@"TIMESTAMP"])
                return [NSString stringWithFormat:@"%g   <- %@", v, CDDate(v)];
            return [NSString stringWithFormat:@"%g", v];
        }
        case SQLITE_BLOB:
            return BlobText(sqlite3_column_blob(st, idx), sqlite3_column_bytes(st, idx));
        default: {
            NSString *t = Flat(S(sqlite3_column_text(st, idx)));
            if ([decl isEqualToString:@"TIMESTAMP"])
                return [NSString stringWithFormat:@"%@   <- %@", t, CDDate(t.doubleValue)];
            return Clip(t, 400);
        }
    }
}

#pragma mark - Row model

@interface PDRecord : NSObject
@property(nonatomic, copy)   NSString *table;
@property(nonatomic, copy)   NSString *via;      /* how this row was reached, e.g. "via ZASSET.ZMOMENT" */
@property(nonatomic)         long long pk;
@property(nonatomic, strong) NSArray<NSString *> *columns;
@property(nonatomic, strong) NSArray<NSString *> *values;
@end

@implementation PDRecord
- (NSString *)valueForColumn:(NSString *)column {
    NSUInteger i = [self.columns indexOfObject:column];
    return i == NSNotFound ? nil : self.values[i];
}
@end

static PDRecord *RecordFromStmt(sqlite3_stmt *st, NSString *table) {
    int n = sqlite3_column_count(st);
    NSMutableArray<NSString *> *cols = [NSMutableArray arrayWithCapacity:(NSUInteger)n];
    NSMutableArray<NSString *> *vals = [NSMutableArray arrayWithCapacity:(NSUInteger)n];
    for (int i = 0; i < n; i++) {
        [cols addObject:S((const unsigned char *)sqlite3_column_name(st, i))];
        [vals addObject:ValueText(st, i)];
    }
    PDRecord *r = [PDRecord new];
    r.table = table;
    r.columns = cols;
    r.values = vals;
    NSUInteger pkIndex = [cols indexOfObject:@"Z_PK"];
    if (pkIndex != NSNotFound) r.pk = [vals[pkIndex] longLongValue];
    return r;
}

#pragma mark - Schema helpers

static NSArray<NSString *> *ColumnsOfTable(sqlite3 *db, NSString *table) {
    NSMutableArray<NSString *> *cols = [NSMutableArray array];
    NSString *sql = [NSString stringWithFormat:@"PRAGMA table_info(%@)", QID(table)];
    sqlite3_stmt *st = NULL;
    if (sqlite3_prepare_v2(db, sql.UTF8String, -1, &st, NULL) == SQLITE_OK) {
        while (sqlite3_step(st) == SQLITE_ROW) {
            NSString *name = S(sqlite3_column_text(st, 1));
            if (name.length) [cols addObject:name];
        }
    }
    sqlite3_finalize(st);
    return cols;
}

static BOOL TableExists(sqlite3 *db, NSString *table) {
    BOOL found = NO;
    sqlite3_stmt *st = NULL;
    if (sqlite3_prepare_v2(db, "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?1", -1, &st, NULL) == SQLITE_OK) {
        sqlite3_bind_text(st, 1, table.UTF8String, -1, SQLITE_TRANSIENT);
        found = (sqlite3_step(st) == SQLITE_ROW);
    }
    sqlite3_finalize(st);
    return found;
}

/* Rows of `table` selected by one column value, capped at `limit` rows. */
static NSArray<PDRecord *> *FetchRowsByValue(sqlite3 *db, NSString *table, NSString *column, long long value, NSUInteger limit) {
    NSMutableArray<PDRecord *> *rows = [NSMutableArray array];
    NSArray<NSString *> *cols = ColumnsOfTable(db, table);
    NSString *order = [cols containsObject:@"Z_PK"] ? @" ORDER BY Z_PK" : @"";
    NSString *sql = [NSString stringWithFormat:@"SELECT * FROM %@ WHERE %@ = ?1%@ LIMIT %lu",
                     QID(table), QID(column), order, (unsigned long)limit];
    sqlite3_stmt *st = NULL;
    if (sqlite3_prepare_v2(db, sql.UTF8String, -1, &st, NULL) != SQLITE_OK) {
        sqlite3_finalize(st);
        return rows;
    }
    sqlite3_bind_int64(st, 1, value);
    while (sqlite3_step(st) == SQLITE_ROW) [rows addObject:RecordFromStmt(st, table)];
    sqlite3_finalize(st);
    return rows;
}

static NSUInteger CountRowsByValue(sqlite3 *db, NSString *table, NSString *column, long long value) {
    NSString *sql = [NSString stringWithFormat:@"SELECT COUNT(*) FROM %@ WHERE %@ = ?1", QID(table), QID(column)];
    sqlite3_stmt *st = NULL;
    NSUInteger n = 0;
    if (sqlite3_prepare_v2(db, sql.UTF8String, -1, &st, NULL) == SQLITE_OK) {
        sqlite3_bind_int64(st, 1, value);
        if (sqlite3_step(st) == SQLITE_ROW) n = (NSUInteger)sqlite3_column_int64(st, 0);
    }
    sqlite3_finalize(st);
    return n;
}

/* Stable key = value pairs for one asset, used both for the diff block and for comparisons. */
static NSArray<NSArray<NSString *> *> *SnapshotPairsFromRecords(NSArray<PDRecord *> *records) {
    NSMutableArray<NSArray<NSString *> *> *pairs = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSNumber *> *seenPerTable = [NSMutableDictionary dictionary];
    for (PDRecord *r in records) {
        NSUInteger index = seenPerTable[r.table] ? seenPerTable[r.table].unsignedIntegerValue : 0;
        seenPerTable[r.table] = @(index + 1);
        NSString *prefix = (index == 0) ? r.table : [NSString stringWithFormat:@"%@[%lu]", r.table, (unsigned long)index];
        for (NSUInteger i = 0; i < r.columns.count; i++)
            [pairs addObject:@[[NSString stringWithFormat:@"%@.%@", prefix, r.columns[i]], r.values[i]]];
    }
    return pairs;
}

#pragma mark - Inspector

@interface PhotoDatabaseInspector ()
@property(nonatomic, copy) NSString *path;
@end

@implementation PhotoDatabaseInspector

- (instancetype)initWithDatabasePath:(NSString *)path {
    if ((self = [super init])) _path = [path copy];
    return self;
}

#pragma mark Connection

- (BOOL)openReadOnly:(sqlite3 **)outDB into:(NSMutableString *)out {
    sqlite3 *db = NULL;
    int rc = sqlite3_open_v2(self.path.fileSystemRepresentation, &db,
                             SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, NULL);
    if (rc != SQLITE_OK) {
        [out appendFormat:@"OPEN FAILED\n  sqlite3 rc=%d (%s)\n  message=%s\n",
                          rc, sqlite3_errstr(rc), db ? sqlite3_errmsg(db) : "(no handle)"];
        [out appendString:@"  note: SQLite needs read access to the -wal/-shm sidecars to see recent writes.\n"];
        if (db) sqlite3_close(db);
        return NO;
    }
    /* Connection-level setting only: it makes reads wait instead of failing with SQLITE_BUSY.
       It does not write to the database and does not change the journal mode. */
    sqlite3_busy_timeout(db, 3000);
    *outDB = db;
    return YES;
}

/* Facts about the files on disk, read via the filesystem only. */
- (NSString *)filePreamble {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSMutableString *o = [NSMutableString string];
    [o appendFormat:@"database  : %@\n", self.path];
    [o appendString:@"open mode : SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX\n"];
    [o appendString:@"busy      : sqlite3_busy_timeout = 3000 ms (connection setting, not a write)\n"];
    [o appendFormat:@"sqlite    : %s\n", sqlite3_libversion()];
    [o appendFormat:@"generated : %@\n", UTCTimestamp()];
    NSDictionary *mainAttrs = [fm attributesOfItemAtPath:self.path error:NULL];
    [o appendFormat:@"main file : %@\n", mainAttrs ? [NSString stringWithFormat:@"%llu bytes", mainAttrs.fileSize] : @"MISSING"];
    for (NSString *suffix in @[@"-wal", @"-shm"]) {
        NSString *sidecar = [self.path stringByAppendingString:suffix];
        NSDictionary *attrs = [fm attributesOfItemAtPath:sidecar error:NULL];
        [o appendFormat:@"%-9s : %@\n", suffix.UTF8String,
                        attrs ? [NSString stringWithFormat:@"%llu bytes (present)", attrs.fileSize] : @"absent"];
    }
    [o appendString:@"\nsafety    : no INSERT/UPDATE/DELETE/DDL, no PRAGMA journal_mode=, no checkpoint, no vacuum.\n"];
    [o appendString:@"            The -wal/-shm sidecars are only read (stat) and never modified by this tool.\n"];
    return o;
}

- (NSArray<NSString *> *)tableNamesInDB:(sqlite3 *)db {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    sqlite3_stmt *st = NULL;
    if (sqlite3_prepare_v2(db, "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name", -1, &st, NULL) == SQLITE_OK) {
        while (sqlite3_step(st) == SQLITE_ROW) {
            NSString *name = S(sqlite3_column_text(st, 0));
            if (name.length) [names addObject:name];
        }
    }
    sqlite3_finalize(st);
    return names;
}

/* Every table that carries a ZASSET foreign key is a candidate child of the asset row.
   This is discovered from the schema instead of being hard-coded, so it survives
   schema changes between iOS versions. */
- (NSArray<NSString *> *)relatedTablesInDB:(sqlite3 *)db from:(NSArray<NSString *> *)tables {
    NSArray<NSString *> *priority = @[@"ZADDITIONALASSETATTRIBUTES", @"ZEXTENDEDATTRIBUTES",
                                      @"ZMEDIAANALYSISASSETATTRIBUTES", @"ZCOMPUTEDASSETATTRIBUTES",
                                      @"ZASSETANALYSISSTATE", @"ZINTERNALRESOURCE",
                                      @"ZCLOUDRESOURCE", @"ZASSETDESCRIPTION"];
    NSMutableArray<NSString *> *found = [NSMutableArray array];
    for (NSString *table in tables) {
        if ([table isEqualToString:@"ZASSET"]) continue;
        if ([ColumnsOfTable(db, table) containsObject:@"ZASSET"]) [found addObject:table];
    }
    NSMutableArray<NSString *> *ordered = [NSMutableArray array];
    for (NSString *name in priority) if ([found containsObject:name]) [ordered addObject:name];
    for (NSString *name in [found sortedArrayUsingSelector:@selector(compare:)])
        if (![ordered containsObject:name]) [ordered addObject:name];
    return ordered;
}

#pragma mark Phase 2 : record collection

/* ZASSET row + every table referencing it + one extra hop for ZASSET-shaped foreign keys
   (a column whose name is also a table name, e.g. ZADDITIONALASSETATTRIBUTES.ZASSETDESCRIPTION). */
- (NSArray<PDRecord *> *)recordsForAsset:(PDRecord *)asset
                                      db:(sqlite3 *)db
                                 related:(NSArray<NSString *> *)related
                                tableSet:(NSSet<NSString *> *)tableSet
                                  notes:(NSMutableArray<NSString *> *)notes {
    NSMutableArray<PDRecord *> *records = [NSMutableArray arrayWithObject:asset];
    NSMutableSet<NSString *> *seen = [NSMutableSet setWithObject:[NSString stringWithFormat:@"ZASSET#%lld", asset.pk]];
    const NSUInteger rowCap = 12;

    for (NSString *table in related) {
        NSUInteger total = CountRowsByValue(db, table, @"ZASSET", asset.pk);
        if (total == 0) continue;
        NSArray<PDRecord *> *rows = FetchRowsByValue(db, table, @"ZASSET", asset.pk, rowCap);
        for (PDRecord *r in rows) {
            NSString *key = [NSString stringWithFormat:@"%@#%lld", r.table, r.pk];
            if ([seen containsObject:key]) continue;
            [seen addObject:key];
            [records addObject:r];
        }
        if (total > rows.count)
            [notes addObject:[NSString stringWithFormat:@"%@ has %lu rows, first %lu shown",
                                                        table, (unsigned long)total, (unsigned long)rows.count]];
    }

    for (PDRecord *parent in [records copy]) {
        for (NSUInteger i = 0; i < parent.columns.count; i++) {
            NSString *column = parent.columns[i];
            if ([column isEqualToString:@"ZASSET"] || ![tableSet containsObject:column]) continue;
            NSString *raw = parent.values[i];
            if (!IsDigits(raw) || raw.longLongValue <= 0) continue;
            NSString *key = [NSString stringWithFormat:@"%@#%@", column, raw];
            if ([seen containsObject:key]) continue;
            [seen addObject:key];
            NSArray<PDRecord *> *rows = FetchRowsByValue(db, column, @"Z_PK", raw.longLongValue, 1);
            for (PDRecord *r in rows) {
                r.via = [NSString stringWithFormat:@"via %@.%@ = %@", parent.table, column, raw];
                [records addObject:r];
            }
        }
    }
    return records;
}

/* Builds and runs the ZASSET lookup for one search term.
   Returns: sql (NSString), binds (NSArray<NSString *>), rows (NSArray<PDRecord *>), error (NSString, optional). */
- (NSDictionary<NSString *, id> *)queryAssetsWithSearch:(NSString *)search
                                                     db:(sqlite3 *)db
                                              assetCols:(NSArray<NSString *> *)assetCols
                                                related:(NSArray<NSString *> *)related
                                                  limit:(NSInteger)limit {
    NSMutableArray<NSString *> *clauses = [NSMutableArray array];
    NSMutableArray<NSString *> *binds = [NSMutableArray array];
    if (search.length) {
        NSString *fragment = [NSString stringWithFormat:@"%%%@%%", LikeEscape(search)];
        if ([assetCols containsObject:@"ZUUID"]) {
            [clauses addObject:@"ZUUID = ?"];
            [binds addObject:search];
            [clauses addObject:@"ZUUID LIKE ? ESCAPE '\\'"];
            [binds addObject:fragment];
        }
        if ([assetCols containsObject:@"ZFILENAME"]) {
            [clauses addObject:@"ZFILENAME LIKE ? ESCAPE '\\'"];
            [binds addObject:fragment];
        }
        if ([assetCols containsObject:@"Z_PK"] && IsDigits(search)) {
            [clauses addObject:@"Z_PK = ?"];
            [binds addObject:search];
        }
        /* Imported files may only be reachable through the original file name. */
        for (NSString *table in related) {
            NSArray<NSString *> *cols = ColumnsOfTable(db, table);
            if ([cols containsObject:@"ZASSET"] && [cols containsObject:@"ZORIGINALFILENAME"]) {
                [clauses addObject:[NSString stringWithFormat:@"Z_PK IN (SELECT ZASSET FROM %@ WHERE ZORIGINALFILENAME LIKE ? ESCAPE '\\')", QID(table)]];
                [binds addObject:fragment];
            }
        }
    }
    NSString *where = clauses.count ? [NSString stringWithFormat:@" WHERE (%@)", [clauses componentsJoinedByString:@" OR "]] : @"";
    NSString *sql = [NSString stringWithFormat:@"SELECT * FROM %@%@ ORDER BY Z_PK DESC LIMIT %ld", QID(@"ZASSET"), where, (long)limit];

    NSMutableArray<PDRecord *> *rows = [NSMutableArray array];
    NSMutableString *error = nil;
    sqlite3_stmt *st = NULL;
    if (sqlite3_prepare_v2(db, sql.UTF8String, -1, &st, NULL) != SQLITE_OK) {
        error = [NSMutableString stringWithFormat:@"prepare failed: %s", sqlite3_errmsg(db)];
    } else {
        for (NSUInteger i = 0; i < binds.count; i++)
            sqlite3_bind_text(st, (int)(i + 1), binds[i].UTF8String, -1, SQLITE_TRANSIENT);
        int rc = SQLITE_OK;
        while ((rc = sqlite3_step(st)) == SQLITE_ROW) [rows addObject:RecordFromStmt(st, @"ZASSET")];
        if (rc != SQLITE_DONE) error = [NSMutableString stringWithFormat:@"step failed: %s", sqlite3_errmsg(db)];
        sqlite3_finalize(st);
    }

    NSMutableDictionary<NSString *, id> *result = [NSMutableDictionary dictionary];
    result[@"sql"] = sql;
    result[@"binds"] = binds;
    result[@"rows"] = rows;
    if (error) result[@"error"] = error;
    return result;
}

#pragma mark Phase 1 (unchanged)

- (NSString *)inspectReport {
    NSMutableString *out=[NSMutableString stringWithString:@"\n"]; sqlite3 *db=NULL;
    int rc=sqlite3_open_v2(self.path.fileSystemRepresentation,&db,SQLITE_OPEN_READONLY|SQLITE_OPEN_FULLMUTEX,NULL);
    if (rc!=SQLITE_OK) { [out appendFormat:@"OPEN FAILED\n  sqlite3 rc=%d\n  message=%@\n",rc,db ? @(sqlite3_errmsg(db)) : @"(no handle)"]; if(db)sqlite3_close(db); return out; }
    [out appendFormat:@"OPEN OK\n  sqlite_version=%s\n  filename=%s\n",sqlite3_libversion(),sqlite3_db_filename(db,"main") ?: "(unknown)"];

    sqlite3_stmt *stmt=NULL;
    const char *sql="SELECT type,name,tbl_name,sql FROM sqlite_master WHERE type IN ('table','index','view','trigger') ORDER BY type,name";
    rc=sqlite3_prepare_v2(db,sql,-1,&stmt,NULL);
    if(rc!=SQLITE_OK){[out appendFormat:@"\nschema query failed: %s\n",sqlite3_errmsg(db)]; sqlite3_close(db); return out;}
    NSMutableArray<NSString *> *tables=[NSMutableArray array];
    NSMutableString *objects=[NSMutableString stringWithString:@"\nSQLITE OBJECTS\n--------------\n"];
    while(sqlite3_step(stmt)==SQLITE_ROW){NSString *type=S(sqlite3_column_text(stmt,0)); NSString *name=S(sqlite3_column_text(stmt,1)); NSString *tbl=S(sqlite3_column_text(stmt,2)); NSString *ddl=S(sqlite3_column_text(stmt,3)); [objects appendFormat:@"%@  %@",type,name]; if(![tbl isEqualToString:@"NULL"]&&![@"(unknown)" isEqualToString:tbl]) [objects appendFormat:@"  table=%@",tbl]; [objects appendFormat:@"\n  SQL: %@\n",ddl]; if([type isEqualToString:@"table"]) [tables addObject:name]; }
    sqlite3_finalize(stmt); [out appendString:objects];

    [out appendString:@"\nTABLE SCHEMAS\n-------------\n"];
    NSMutableArray<NSString *> *candidateLines=[NSMutableArray array];
    NSSet *keywords=[NSSet setWithArray:@[@"screen",@"screenshot",@"capture",@"subtype",@"media",@"kind",@"source",@"import",@"camera"]];
    for(NSString *table in tables){
        NSString *pragma=[NSString stringWithFormat:@"PRAGMA table_info('%@')",Q(table)];
        sqlite3_stmt *ts=NULL; if(sqlite3_prepare_v2(db,pragma.UTF8String,-1,&ts,NULL)!=SQLITE_OK){[out appendFormat:@"\n%@\n  [table_info failed: %s]\n",table,sqlite3_errmsg(db)];continue;}
        [out appendFormat:@"\nTABLE %@\n",table];
        while(sqlite3_step(ts)==SQLITE_ROW){NSString *name=S(sqlite3_column_text(ts,1)); NSString *type=S(sqlite3_column_text(ts,2)); int notnull=sqlite3_column_int(ts,3); NSString *def=S(sqlite3_column_text(ts,4)); int pk=sqlite3_column_int(ts,5); [out appendFormat:@"  cid=%d  name=%@  type=%@  notnull=%d  default=%@  pk=%d\n",sqlite3_column_int(ts,0),name,type,notnull,def,pk]; NSString *lower=name.lowercaseString; for(NSString *k in keywords) if([lower containsString:k]) {[candidateLines addObject:[NSString stringWithFormat:@"  %@.%@  (matched: %@)",table,name,k]]; break;}}
        sqlite3_finalize(ts);
    }
    [out appendString:@"\nPOSSIBLE SCREENSHOT-RELATED COLUMNS\n----------------------------------\n"]; if(candidateLines.count) for(NSString *line in candidateLines) [out appendFormat:@"%@\n",line]; else [out appendString:@"None found by name heuristic. This is not proof that no screenshot metadata exists.\n"];
    [out appendString:@"\nSAFETY\n------\nDatabase opened SQLITE_OPEN_READONLY. No INSERT/UPDATE/DELETE/DDL/checkpoint is executed by this inspector.\n"];
    sqlite3_close(db); return out;
}

#pragma mark Phase 2 : asset list

- (NSString *)assetListReportWithLimit:(NSInteger)limit {
    NSMutableString *out = [NSMutableString string];
    [out appendString:@"ASSET LIST - Photos.sqlite (Phase 2, READ-ONLY)\n"];
    [out appendString:@"=================================================\n\n"];
    [out appendString:[self filePreamble]];

    sqlite3 *db = NULL;
    if (![self openReadOnly:&db into:out]) return out;

    NSArray<NSString *> *tables = [self tableNamesInDB:db];
    NSArray<NSString *> *assetCols = ColumnsOfTable(db, @"ZASSET");
    if (!TableExists(db, @"ZASSET")) {
        [out appendString:@"\n[ZASSET] table not found - this is not a Photos asset database.\n"];
        sqlite3_close(db);
        return out;
    }
    NSArray<NSString *> *related = [self relatedTablesInDB:db from:tables];

    /* How many assets exist at all. */
    long long total = 0;
    sqlite3_stmt *st = NULL;
    if (sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM \"ZASSET\"", -1, &st, NULL) == SQLITE_OK) {
        if (sqlite3_step(st) == SQLITE_ROW) total = sqlite3_column_int64(st, 0);
    }
    sqlite3_finalize(st);

    [out appendFormat:@"\nZASSET total rows : %lld\n", total];
    [out appendFormat:@"related tables   : %lu -> %@\n", (unsigned long)related.count, [related componentsJoinedByString:@", "]];

    /* Census: which (ZKIND, ZKINDSUBTYPE, ZSAVEDASSETTYPE) combinations exist, and how many rows each has.
       This is the cheapest way to see whether screenshots form their own group. */
    NSMutableArray<NSString *> *censusCols = [NSMutableArray array];
    for (NSString *col in @[@"ZKIND", @"ZKINDSUBTYPE", @"ZSAVEDASSETTYPE"])
        if ([assetCols containsObject:col]) [censusCols addObject:col];
    if (censusCols.count == 3) {
        [out appendString:@"\nZASSET CLASS CENSUS (grouped by ZKIND / ZKINDSUBTYPE / ZSAVEDASSETTYPE)\n"];
        [out appendString:@"---------------------------------------------------------------------------\n"];
        [out appendString:@"  ZKIND  ZKINDSUBTYPE  ZSAVEDASSETTYPE  COUNT    sample file\n"];
        NSString *sql = @"SELECT IFNULL(ZKIND,-1), IFNULL(ZKINDSUBTYPE,-1), IFNULL(ZSAVEDASSETTYPE,-1), COUNT(*) "
                         "FROM \"ZASSET\" GROUP BY 1,2,3 ORDER BY COUNT(*) DESC";
        sqlite3_stmt *cs = NULL;
        if (sqlite3_prepare_v2(db, sql.UTF8String, -1, &cs, NULL) == SQLITE_OK) {
            while (sqlite3_step(cs) == SQLITE_ROW) {
                long long k = sqlite3_column_int64(cs, 0), sub = sqlite3_column_int64(cs, 1), saved = sqlite3_column_int64(cs, 2), n = sqlite3_column_int64(cs, 3);
                NSString *sample = @"";
                sqlite3_stmt *ss = NULL;
                NSString *sampleSQL = @"SELECT ZFILENAME FROM \"ZASSET\" WHERE IFNULL(ZKIND,-1)=?1 AND IFNULL(ZKINDSUBTYPE,-1)=?2 AND IFNULL(ZSAVEDASSETTYPE,-1)=?3 LIMIT 1";
                if (sqlite3_prepare_v2(db, sampleSQL.UTF8String, -1, &ss, NULL) == SQLITE_OK) {
                    sqlite3_bind_int64(ss, 1, k); sqlite3_bind_int64(ss, 2, sub); sqlite3_bind_int64(ss, 3, saved);
                    if (sqlite3_step(ss) == SQLITE_ROW) sample = Flat(S(sqlite3_column_text(ss, 0)));
                }
                sqlite3_finalize(ss);
                [out appendFormat:@"  %-6lld %-13lld %-16lld %-8lld %@\n", k, sub, saved, n, sample];
            }
        }
        sqlite3_finalize(cs);
        [out appendString:@"  (-1 means the column is NULL for that row)\n"];
    } else {
        [out appendFormat:@"\nclass census skipped: ZASSET is missing some of %@\n", [@[@"ZKIND", @"ZKINDSUBTYPE", @"ZSAVEDASSETTYPE"] componentsJoinedByString:@", "]];
    }

    /* Newest rows. */
    NSString *listSQL = [NSString stringWithFormat:@"SELECT * FROM \"ZASSET\" ORDER BY Z_PK DESC LIMIT %ld", (long)limit];
    [out appendFormat:@"\nLATEST %ld ZASSET ROWS\n", (long)limit];
    [out appendString:@"---------------------\n"];
    [out appendFormat:@"sql: %@\n\n", listSQL];
    NSMutableArray<PDRecord *> *assets = [NSMutableArray array];
    sqlite3_stmt *ls = NULL;
    if (sqlite3_prepare_v2(db, listSQL.UTF8String, -1, &ls, NULL) == SQLITE_OK) {
        while (sqlite3_step(ls) == SQLITE_ROW) [assets addObject:RecordFromStmt(ls, @"ZASSET")];
    } else {
        [out appendFormat:@"query failed: %s\n", sqlite3_errmsg(db)];
    }
    sqlite3_finalize(ls);

    for (NSUInteger i = 0; i < assets.count; i++) {
        PDRecord *a = assets[i];
        NSMutableArray<NSString *> *parts = [NSMutableArray array];
        [parts addObject:[NSString stringWithFormat:@"Z_PK=%@", [a valueForColumn:@"Z_PK"] ?: @"?"]];
        for (NSString *col in @[@"ZKIND", @"ZKINDSUBTYPE", @"ZSAVEDASSETTYPE", @"ZUNIFORMTYPEIDENTIFIER", @"ZFILENAME", @"ZDATECREATED", @"ZUUID"])
            if ([a valueForColumn:col]) [parts addObject:[NSString stringWithFormat:@"%@=%@", col, [a valueForColumn:col]]];
        [out appendFormat:@"%3lu  %@\n", (unsigned long)(i + 1), [parts componentsJoinedByString:@"  "]];
    }
    if (!assets.count) [out appendString:@"(no rows)\n"];

    [out appendString:@"\nNEXT STEP\n---------\n"];
    [out appendString:@"Open \"Asset\" and dump one real screenshot, one imported PNG and one imported HEIF/JPEG,\n"];
    [out appendString:@"then compare the three dumps field by field.\n"];
    sqlite3_close(db);
    return out;
}

#pragma mark Phase 2 : single asset dump

- (NSString *)assetDumpReportForSearch:(NSString *)search {
    NSMutableString *out = [NSMutableString string];
    [out appendString:@"ASSET DUMP - Photos.sqlite (Phase 2, READ-ONLY)\n"];
    [out appendString:@"==============================================\n\n"];
    [out appendString:[self filePreamble]];

    sqlite3 *db = NULL;
    if (![self openReadOnly:&db into:out]) return out;

    NSArray<NSString *> *tables = [self tableNamesInDB:db];
    NSSet<NSString *> *tableSet = [NSSet setWithArray:tables];
    if (!TableExists(db, @"ZASSET")) {
        [out appendString:@"\n[ZASSET] table not found - this is not a Photos asset database.\n"];
        sqlite3_close(db);
        return out;
    }
    NSArray<NSString *> *assetCols = ColumnsOfTable(db, @"ZASSET");
    NSArray<NSString *> *related = [self relatedTablesInDB:db from:tables];

    NSDictionary<NSString *, id> *query = [self queryAssetsWithSearch:search db:db assetCols:assetCols related:related limit:20];
    NSString *sql = query[@"sql"];
    NSArray<NSString *> *binds = query[@"binds"];
    NSArray<PDRecord *> *assets = query[@"rows"];
    NSString *error = query[@"error"];

    [out appendString:@"\nSEARCH\n------\n"];
    [out appendFormat:@"term       : %@\n", search.length ? search : @"(empty -> newest asset)"];
    [out appendFormat:@"sql        : %@\n", sql];
    if (binds.count) {
        NSMutableArray<NSString *> *bs = [NSMutableArray array];
        for (NSUInteger i = 0; i < binds.count; i++) [bs addObject:[NSString stringWithFormat:@"?%lu=%@", (unsigned long)(i + 1), Flat(binds[i])]];
        [out appendFormat:@"bindings   : %@\n", [bs componentsJoinedByString:@"  "]];
    } else {
        [out appendString:@"bindings   : none (no search term matched a known column)\n"];
    }
    [out appendFormat:@"related    : %lu table(s) reference ZASSET -> %@\n", (unsigned long)related.count, [related componentsJoinedByString:@", "]];
    if (error) [out appendFormat:@"ERROR      : %@\n", error];
    [out appendFormat:@"matches    : %lu\n", (unsigned long)assets.count];

    if (!assets.count) {
        [out appendString:@"\nNo ZASSET row matched. Nothing was written to the database.\n"];
        sqlite3_close(db);
        return out;
    }

    const NSUInteger dumpCap = 5;
    if (assets.count > dumpCap)
        [out appendFormat:@"\nNOTE: %lu matches, first %lu are dumped in full.\n", (unsigned long)assets.count, (unsigned long)dumpCap];

    for (NSUInteger i = 0; i < assets.count; i++) {
        PDRecord *asset = assets[i];
        [out appendString:@"\n================================================================================\n"];
        [out appendFormat:@"ASSET %lu / %lu   Z_PK=%lld\n  ZFILENAME=%@\n  ZUUID=%@\n",
                          (unsigned long)(i + 1), (unsigned long)assets.count, asset.pk,
                          [asset valueForColumn:@"ZFILENAME"] ?: @"(null)",
                          [asset valueForColumn:@"ZUUID"] ?: @"(null)"];
        [out appendString:@"================================================================================\n"];
        if (i >= dumpCap) {
            [out appendString:@"(not dumped in full - see the list above)\n"];
            continue;
        }

        NSMutableArray<NSString *> *notes = [NSMutableArray array];
        NSArray<PDRecord *> *records = [self recordsForAsset:asset db:db related:related tableSet:tableSet notes:notes];

        for (PDRecord *r in records) {
            [out appendFormat:@"\n[%@]   Z_PK=%lld%@\n", r.table, r.pk, r.via.length ? [NSString stringWithFormat:@"   (%@)", r.via] : @""];
            for (NSUInteger c = 0; c < r.columns.count; c++)
                [out appendFormat:@"  %@ = %@\n", Pad(r.columns[c], 38), r.values[c]];
        }

        /* Prove that the to-one column on ZASSET and the reverse lookup agree. */
        [out appendString:@"\nRELATION CHECK (ZASSET to-one column value vs. rows found through ZASSET=<pk>)\n"];
        [out appendString:@"-----------------------------------------------------------------------------------\n"];
        BOOL anyCheck = NO;
        for (NSUInteger c = 0; c < asset.columns.count; c++) {
            NSString *column = asset.columns[c];
            if ([column isEqualToString:@"ZASSET"] || ![tableSet containsObject:column]) continue;
            anyCheck = YES;
            NSString *raw = asset.values[c];
            NSString *verdict = nil;
            if (!IsDigits(raw)) {
                verdict = @"not an integer column value";
            } else if (raw.longLongValue <= 0) {
                verdict = @"0 = unset, no row expected";
            } else {
                NSArray<PDRecord *> *rows = FetchRowsByValue(db, column, @"Z_PK", raw.longLongValue, 1);
                verdict = rows.count ? [NSString stringWithFormat:@"%@.Z_PK=%lld  MATCH", column, rows[0].pk]
                                     : [NSString stringWithFormat:@"%@ has no row with Z_PK=%@  MISMATCH", column, raw];
            }
            [out appendFormat:@"  ZASSET.%@ = %@   ->   %@\n", Pad(column, 36), Pad(raw, 12), verdict];
        }
        if (!anyCheck) [out appendString:@"  No ZASSET column resolves to an existing table name in this schema.\n"];

        for (NSString *note in notes) [out appendFormat:@"  note: %@\n", note];

        [out appendString:@"\nDIFF BLOCK (stable key = value lines; dump several assets and diff the blocks)\n"];
        [out appendString:@"----------------------------------------------------------------------------\n"];
        for (NSArray<NSString *> *pair in SnapshotPairsFromRecords(records))
            [out appendFormat:@"%@ = %@\n", pair[0], pair[1]];
    }

    [out appendString:@"\nSAFETY\n------\n"];
    [out appendString:@"The database was opened SQLITE_OPEN_READONLY. No INSERT/UPDATE/DELETE, no DDL,\n"];
    [out appendString:@"no journal_mode change and no checkpoint was executed.\n"];
    sqlite3_close(db);
    return out;
}

#pragma mark Phase 2 : comparison

- (NSString *)assetCompareReportForSearches:(NSArray<NSString *> *)searches {
    NSMutableString *out = [NSMutableString string];
    [out appendString:@"ASSET COMPARE - Photos.sqlite (Phase 2, READ-ONLY)\n"];
    [out appendString:@"=================================================\n\n"];
    [out appendString:[self filePreamble]];

    sqlite3 *db = NULL;
    if (![self openReadOnly:&db into:out]) return out;

    NSArray<NSString *> *tables = [self tableNamesInDB:db];
    NSSet<NSString *> *tableSet = [NSSet setWithArray:tables];
    if (!TableExists(db, @"ZASSET") || searches.count < 2) {
        [out appendString:@"\n[ZASSET] missing, or fewer than two search terms were supplied.\n"];
        sqlite3_close(db);
        return out;
    }
    NSArray<NSString *> *assetCols = ColumnsOfTable(db, @"ZASSET");
    NSArray<NSString *> *related = [self relatedTablesInDB:db from:tables];

    NSMutableArray<NSMutableDictionary<NSString *, NSString *> *> *maps = [NSMutableArray array];
    NSMutableArray<NSString *> *labels = [NSMutableArray array];
    NSMutableArray<NSString *> *order = [NSMutableArray array];
    NSMutableSet<NSString *> *orderSet = [NSMutableSet set];

    [out appendString:@"\nSEARCHES\n--------\n"];
    for (NSUInteger i = 0; i < searches.count; i++) {
        NSString *term = searches[i];
        unichar letterChar = (unichar)('A' + (i % 26));
        NSString *letter = [NSString stringWithCharacters:&letterChar length:1];
        NSDictionary<NSString *, id> *query = [self queryAssetsWithSearch:term db:db assetCols:assetCols related:related limit:5];
        NSString *error = query[@"error"];
        NSArray<PDRecord *> *assets = query[@"rows"];
        if (!assets.count) {
            [out appendFormat:@"  %@: %@  -> NO MATCH%@\n", letter, term, error ? [NSString stringWithFormat:@"  (%@)", error] : @""];
            continue;
        }
        PDRecord *asset = assets[0];
        [out appendFormat:@"  %@: %@  -> Z_PK=%lld  ZFILENAME=%@  ZUNIFORMTYPEIDENTIFIER=%@%@\n",
                          letter, term, asset.pk,
                          [asset valueForColumn:@"ZFILENAME"] ?: @"(null)",
                          [asset valueForColumn:@"ZUNIFORMTYPEIDENTIFIER"] ?: @"(null)",
                          assets.count > 1 ? [NSString stringWithFormat:@"   (%lu matches, using the first)", (unsigned long)assets.count] : @""];
        NSMutableArray<NSString *> *notes = [NSMutableArray array];
        NSArray<PDRecord *> *records = [self recordsForAsset:asset db:db related:related tableSet:tableSet notes:notes];
        NSMutableDictionary<NSString *, NSString *> *map = [NSMutableDictionary dictionary];
        for (NSArray<NSString *> *pair in SnapshotPairsFromRecords(records)) {
            map[pair[0]] = pair[1];
            if (![orderSet containsObject:pair[0]]) { [orderSet addObject:pair[0]]; [order addObject:pair[0]]; }
        }
        [maps addObject:map];
        [labels addObject:letter];
    }

    if (maps.count < 2) {
        [out appendString:@"\nFewer than two assets could be resolved, so there is nothing to compare.\n"];
        sqlite3_close(db);
        return out;
    }

    NSMutableArray<NSString *> *differing = [NSMutableArray array];
    NSUInteger identical = 0;
    for (NSString *key in order) {
        NSMutableSet<NSString *> *distinct = [NSMutableSet set];
        for (NSMutableDictionary<NSString *, NSString *> *map in maps) [distinct addObject:map[key] ?: @"(absent)"];
        if (distinct.count > 1) [differing addObject:key]; else identical++;
    }

    [out appendFormat:@"\nfields compared : %lu (union of all asset dumps)\n", (unsigned long)order.count];
    [out appendFormat:@"identical       : %lu\n", (unsigned long)identical];
    [out appendFormat:@"differing       : %lu\n", (unsigned long)differing.count];

    [out appendString:@"\nDIFFERING FIELDS\n----------------\n"];
    if (!differing.count) {
        [out appendString:@"None. The compared assets look identical field by field - which would itself be a finding,\n"];
        [out appendString:@"so double-check that the search terms really resolved to different assets.\n"];
    }
    for (NSString *key in differing) {
        [out appendFormat:@"%@\n", key];
        for (NSUInteger i = 0; i < maps.count; i++)
            [out appendFormat:@"    %@ = %@\n", labels[i], maps[i][key] ?: @"(absent)"];
        [out appendString:@"\n"];
    }

    if (identical)
        [out appendFormat:@"IDENTICAL FIELDS: %lu (omitted; see the per-asset dumps)\n", (unsigned long)identical];

    [out appendString:@"\nREMINDER\n--------\n"];
    [out appendString:@"A difference between two assets is an observation, not a proof of the screenshot flag.\n"];
    [out appendString:@"Repeat it with more samples before treating any field as the classification.\n"];
    sqlite3_close(db);
    return out;
}

@end
