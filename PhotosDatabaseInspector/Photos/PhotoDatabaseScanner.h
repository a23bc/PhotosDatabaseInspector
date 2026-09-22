#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PhotoDatabaseScanner : NSObject
+ (instancetype)shared;
- (NSString *)scanReport;
@end

NS_ASSUME_NONNULL_END
