
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface LRCommonUtils : NSObject
+ (NSURL*) getShareBugReportPath: (NSString *)groupIndentifier;
+ (NSString *)getHardware;
+ (NSString *)getOsBuild;
+ (void)recursivelyDescribeTo:(NSMutableString *)buffer viewController:(UIViewController *)viewController indent:(NSUInteger)indent;
+ (NSString *)randomStringWithLength:(NSUInteger)len;
@end

NS_ASSUME_NONNULL_END
