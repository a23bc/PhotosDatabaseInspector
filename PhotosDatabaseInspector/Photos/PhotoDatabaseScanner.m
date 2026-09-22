#import "PhotoDatabaseScanner.h"
#import "PhotoDatabaseInspector.h"
#include <sys/stat.h>
#include <errno.h>
#include <string.h>

static NSString *FileInfo(NSString *path) {
    struct stat st;
    if (stat(path.fileSystemRepresentation, &st) != 0) return [NSString stringWithFormat:@"missing (errno=%d: %s)", errno, strerror(errno)];
    return [NSString stringWithFormat:@"%llu bytes, mtime=%lld, inode=%llu", (unsigned long long)st.st_size, (long long)st.st_mtime, (unsigned long long)st.st_ino];
}

@implementation PhotoDatabaseScanner
+ (instancetype)shared { static PhotoDatabaseScanner *s; static dispatch_once_t once; dispatch_once(&once, ^{ s=[self new]; }); return s; }

- (NSString *)scanReport {
    NSString *root=@"/var/mobile/Media/PhotoData";
    NSFileManager *fm=NSFileManager.defaultManager;
    NSMutableString *out=[NSMutableString stringWithFormat:@"PHOTOS DATABASE INSPECTOR 0.1.0\nREAD-ONLY — NO DATABASE WRITES\n================================\n\nROOT\n----\n%@\n\n",root];
    BOOL isDir=NO;
    if (![fm fileExistsAtPath:root isDirectory:&isDir] || !isDir) { [out appendString:@"[NOT FOUND] PhotoData directory\n"]; return out; }
    NSMutableArray<NSString *> *dbs=[NSMutableArray array];
    NSDirectoryEnumerator *e=[fm enumeratorAtPath:root];
    for (NSString *rel in e) {
        @autoreleasepool {
            NSString *name=rel.lastPathComponent.lowercaseString;
            if ([name hasSuffix:@".sqlite"] || [name hasSuffix:@".sqlite3"]) [dbs addObject:[root stringByAppendingPathComponent:rel]];
        }
    }
    [dbs sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    [out appendFormat:@"SQLite databases found: %lu\n\n",(unsigned long)dbs.count];
    if (!dbs.count) { [out appendString:@"No .sqlite/.sqlite3 files were found.\n"]; return out; }
    for (NSString *db in dbs) {
        [out appendFormat:@"DATABASE\n--------\n%@\n  %@\n",db,FileInfo(db)];
        NSString *wal=[db stringByAppendingString:@"-wal"]; NSString *shm=[db stringByAppendingString:@"-shm"];
        [out appendFormat:@"  wal: %@\n  shm: %@\n\n", [fm fileExistsAtPath:wal] ? FileInfo(wal) : @"absent", [fm fileExistsAtPath:shm] ? FileInfo(shm) : @"absent"];
        PhotoDatabaseInspector *ins=[[PhotoDatabaseInspector alloc] initWithDatabasePath:db];
        [out appendString:[ins inspectReport]];
        [out appendString:@"\n============================================================\n\n"];
    }
    return out;
}
@end
