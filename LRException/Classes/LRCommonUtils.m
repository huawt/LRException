
#import "LRCommonUtils.h"
#import <sys/sysctl.h>

@implementation LRCommonUtils

+ (NSURL*) getShareBugReportPath: (NSString *)groupIndentifier {
    NSString *identifier = groupIndentifier;
    if (identifier == nil || identifier.length == 0) {
        NSString *bi = [[NSBundle mainBundle].infoDictionary objectForKey:@"CFBundleIdentifier"];
        identifier = [NSString stringWithFormat:@"group.%@", bi];
        identifier = [identifier stringByReplacingOccurrencesOfString:@"com." withString: @""];
    }
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSURL *documentsURL = [fileManager containerURLForSecurityApplicationGroupIdentifier:identifier];
    return [documentsURL URLByAppendingPathComponent:@"bug.txt" isDirectory:NO];
}

+ (NSString*)getHardware {
    static NSString* hardware;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        size_t size;
        sysctlbyname("hw.machine", NULL, &size, NULL, 0);
        char *machine = malloc(size);
        sysctlbyname("hw.machine", machine, &size, NULL, 0);
        hardware = @(machine);
        free(machine);
    });
    return hardware;
}

+ (NSString*)getOsBuild {
    static NSString* build;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        size_t size;
        sysctlbyname("kern.osversion", NULL, &size, NULL, 0);
        char *osversion = malloc(size);
        sysctlbyname("kern.osversion", osversion, &size, NULL, 0);
        build = @(osversion);
        free(osversion);
    });
    return build;
}

+ (void)recursivelyDescribeTo:(NSMutableString*)buffer viewController:(UIViewController*)viewController indent:(NSUInteger)indent {
    [buffer appendString:[@"" stringByPaddingToLength:@"   | ".length*indent withString:@"   | " startingAtIndex:0]]; // indent
    [buffer appendFormat:@"%@\n", viewController]; // the view controller
    
    for (UIViewController* vc in viewController.childViewControllers) {
        [self recursivelyDescribeTo:buffer viewController:vc indent:indent+1];
    }
    if (viewController.presentedViewController) {
        [buffer appendString:@"Presented:\n"];
        [self recursivelyDescribeTo:buffer viewController:viewController.presentedViewController indent:indent+1];
    }
}

+ (NSString*)randomStringWithLength:(NSUInteger)len {
    static NSString* const c = @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
    NSMutableString* mutableStr = [[NSMutableString alloc] initWithCapacity:len];
    for (NSInteger i = 0; i < len; ++i) {
        NSUInteger idx = arc4random_uniform((u_int32_t)[c length]);
        [mutableStr appendFormat:@"%C", [c characterAtIndex:idx]];
    }
    return [NSString stringWithString:mutableStr];
}

@end
