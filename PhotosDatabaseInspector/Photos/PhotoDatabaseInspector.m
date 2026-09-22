#import "PhotoDatabaseInspector.h"
#import <sqlite3.h>

@interface PhotoDatabaseInspector ()
@property(nonatomic, copy) NSString *path;
@end

@implementation PhotoDatabaseInspector
- (instancetype)initWithDatabasePath:(NSString *)path { if ((self=[super init])) _path=[path copy]; return self; }

static NSString *S(const unsigned char *v) { return v ? [NSString stringWithUTF8String:(const char *)v] ?: @"(invalid utf8)" : @"NULL"; }
static NSString *Q(NSString *identifier) { return [identifier stringByReplacingOccurrencesOfString:@"'" withString:@"''"]; }

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
@end
