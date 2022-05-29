
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface LRExceptionUtil : NSObject
+ (void)reportBugIfPresent;
+ (void)registerForUncaughtExceptionsAndSignals;
@end

NS_ASSUME_NONNULL_END
