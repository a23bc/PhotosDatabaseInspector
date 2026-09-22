#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PhotoDatabaseInspector : NSObject
- (instancetype)initWithDatabasePath:(NSString *)path;
- (NSString *)inspectReport;
@end

NS_ASSUME_NONNULL_END
