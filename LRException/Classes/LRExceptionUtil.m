
#import "LRExceptionUtil.h"
#import "LRCommonUtils.h"
#import <UIKit/UIKit.h>
#import <execinfo.h>
#import <mach-o/dyld.h>
#import "UIAlertController+LRExtension.h"

@interface LRExceptionUtil ()
+ (void)writeStackTrace:(void **)frames length:(NSInteger)len intoString:(NSMutableString *)buffer;
+ (void)writeRegistersWithContext:(void *)context intoString:(NSMutableString *)buffer;
+ (void)writeExceptionBuffer:(NSString *)buffer;
+ (void)sendAssertionFailureHTTP:(NSString *)text reportUdid:(BOOL)reportUdid adaptiveConn:(BOOL)adaptiveConn;
@end

static const int monitored_signals[] = {
    SIGABRT, SIGBUS, SIGFPE, SIGILL, SIGSEGV, SIGQUIT, SIGEMT,
};

/** @internal
 * number of signals in the fatal signals list */
static const int monitored_signals_count = (sizeof(monitored_signals) / sizeof(monitored_signals[0]));

/// Previous registered handler
static NSUncaughtExceptionHandler *LRPreviousUncaughtExceptionHandler;

/*  UncaughtExceptionHandler
 *
 *    Handle uncaught exceptions
 */

static void UncaughtExceptionHandler(NSException *exception) {
    /*
     *  Extract the call stack
     */
    
    // NSArray<NSString*>* symbols = [exception callStackSymbols];
    NSArray<NSNumber *> *callStack = [exception callStackReturnAddresses];
    NSUInteger len = callStack.count;
    void **frames = malloc(sizeof(void *) * len);  // new void *[len];
    
    for (NSInteger i = 0; i < len; ++i) {
        frames[i] = (void *)callStack[i].unsignedIntegerValue;
    }
    
    /*
     *  Now format into a message for sending to the server
     */
    
    NSMutableString *buffer = [[NSMutableString alloc] initWithCapacity:4096];
    
    [buffer appendFormat:@"device %@\n", [LRCommonUtils getHardware]];
    [buffer appendFormat:@"iOS version %@ (%@)\n\n",
     [[UIDevice currentDevice] systemVersion],
     [LRCommonUtils getOsBuild]];
    [buffer appendString:@"Uncaught Exception\n"];
    [buffer appendFormat:@"Exception Name: %@\n", [exception name]];
    [buffer appendFormat:@"Exception Reason: %@\n", [exception reason]];
    [buffer appendFormat:@"Exception User Info: %@\n", [exception userInfo]];
    if ([[exception reason] isEqualToString:@"Can't add self as subview"]) {  // debug push view onto self problem
        @try {
            [buffer appendString:@"View controller hierarchy: \n"];
            [LRCommonUtils recursivelyDescribeTo:buffer
                                  viewController:[UIApplication sharedApplication].keyWindow.rootViewController
                                          indent:0];
        } @catch (id exception) {
        }
    }
    [LRExceptionUtil writeStackTrace:frames length:len intoString:buffer];
    
    free(frames);
    [LRExceptionUtil writeExceptionBuffer:buffer];
    NSLog(@"test-----Error %@", buffer);
    
    if (LRPreviousUncaughtExceptionHandler) {
        LRPreviousUncaughtExceptionHandler(exception);
    }
}

/*  SignalHandler
 *
 *    Handle uncaught signals
 */
static void SignalHandler(int sig, siginfo_t *info, void *context) {
    // NSArray<NSString*>* symbols = [NSThread callStackSymbols];
    void *frames[128];
    int len = backtrace(frames, 128);
    
    /*
     *  Now format into a message for sending to the server
     */
    
    NSMutableString *buffer = [[NSMutableString alloc] initWithCapacity:4096];
    NSString *version = [[NSBundle mainBundle].infoDictionary objectForKey:@"CFBundleShortVersionString"];
    [buffer appendFormat:@"imo version %@\n\n", version];
    [buffer appendFormat:@"device %@\n", [LRCommonUtils getHardware]];
    [buffer appendFormat:@"iOS version %@ (%@)\n\n",
     [[UIDevice currentDevice] systemVersion],
     [LRCommonUtils getOsBuild]];
    [buffer appendString:@"Uncaught Signal\n"];
    [buffer appendFormat:@"si_signo    %d\n", info->si_signo];
    [buffer appendFormat:@"si_code     %d\n", info->si_code];
    [buffer appendFormat:@"si_value    %d\n", info->si_value.sival_int];
    [buffer appendFormat:@"si_errno    %d\n", info->si_errno];
    [buffer appendFormat:@"si_addr     0x%08" PRIXPTR @"\n", (uintptr_t)info->si_addr];
    [buffer appendFormat:@"si_status   %d\n", info->si_status];
    if ([NSThread currentThread].threadDictionary[@"byebyeinfo"]) {
        @try {
            [buffer appendFormat:@"Bye bye extra information: %@\n",
             [NSThread currentThread].threadDictionary[@"byebyeinfo"]];
        } @catch (id exception) {
        }
    }
    if ([NSThread currentThread].threadDictionary[@"ctdebugtext"]) {
        @try {
            [buffer appendFormat:@"Core Text crash debug: %@\n",
             [NSThread currentThread].threadDictionary[@"ctdebugtext"]];
        } @catch (id exception) {
        }
    }
    [LRExceptionUtil writeRegistersWithContext:context intoString:buffer];
    
    if (len >= 2) {
        // Remove first two lines of stack trace from backtrace(), which are always SignalHandler and _sigtramp,
        // and add in the value of the PC register as the first line, as it indicates the actual location of crash
#if !TARGET_IPHONE_SIMULATOR
        mcontext_t mctx = ((ucontext_t *)context)->uc_mcontext;
        frames[1] = (void *)mctx->__ss.__pc;
#endif
        [LRExceptionUtil writeStackTrace:frames + 1 length:len - 1 intoString:buffer];
    }
    
    [LRExceptionUtil writeExceptionBuffer:buffer];
    NSLog(@"Error %@", buffer);
    
    /*
     * XUAN tells that this part is used to forward the signal to default handler
     * but he doesn't think this works
     * update from Yessen, you can't remove this, because app will stay in runtime,
     * if you don't propagate the signal to the os
     */
    struct sigaction mySigAction;
    mySigAction.sa_handler = SIG_DFL;
    mySigAction.sa_flags = 0;
    sigemptyset(&mySigAction.sa_mask);
    sigaction(sig, &mySigAction, NULL);
    raise(sig);
}

/*  SetupUncaughtSignals
 *
 *    Set up the uncaught signals
 */

static void SetupUncaughtSignals() {
    struct sigaction mySigAction;
    mySigAction.sa_sigaction = SignalHandler;
    mySigAction.sa_flags = SA_SIGINFO;
    
    sigemptyset(&mySigAction.sa_mask);
    for (int i = 0; i < monitored_signals_count; ++i) {
        sigaction(monitored_signals[i], &mySigAction, NULL);
    }
    // sigaction(SIGALRM, &mySigAction, NULL);
    // sigaction(SIGXCPU, &mySigAction, NULL);
    // sigaction(SIGXFSZ, &mySigAction, NULL);
}

// Handle assertion failures
void AssertionHandler(const char *condition, const char *obj_name, id obj, const char *func_name, int line,
                      BOOL reportUdid, BOOL adaptiveConn) {
    // NSArray<NSString*>* symbols = [NSThread callStackSymbols];
    void *frames[128];
    int len = backtrace(frames, 128);
    
    /*
     *  Now format into a message for sending to the server
     */
    
    NSMutableString *buffer = [[NSMutableString alloc] initWithCapacity:4096];
    NSString *version = [[NSBundle mainBundle].infoDictionary objectForKey:@"CFBundleShortVersionString"];
    [buffer appendFormat:@"imo version %@\n\n", version];
    [buffer appendFormat:@"device %@\n", [LRCommonUtils getHardware]];
    [buffer appendFormat:@"iOS version %@ (%@)\n\n",
     [[UIDevice currentDevice] systemVersion],
     [LRCommonUtils getOsBuild]];
    [buffer appendString:@"Assertion failure:\n"];
    [buffer appendFormat:@"%s:%d: failed assertion '%s'", func_name, line, condition];
    if (obj_name)
        [buffer appendFormat:@" with %s = %@", obj_name, obj];
    [buffer appendString:@"\n\n"];
    [LRExceptionUtil writeStackTrace:frames length:len intoString:buffer];
    [LRExceptionUtil sendAssertionFailureHTTP:buffer reportUdid:reportUdid adaptiveConn:adaptiveConn];
    
    NSMutableString *text = [NSMutableString stringWithFormat:@"Failed: %s", condition];
    [text appendFormat:@" %s:%d", func_name, line];
    if (obj_name) {
        [text appendFormat:@"\n%s = %@", obj_name, obj];
    }
    
#if defined(ADHOC) || defined(DEBUG)
    NSLog(@"%@", buffer);
    
    // even though showToast is thread-safe, we dispatch to ensure that InteractionManager will have been set up,
    // because assert could have been called during InteractionManager init
    dispatch_async(dispatch_get_main_queue(), ^{
        [[UIAlertController alertControllerWithTitle:@"Error Report"
                                             message:text
                                      preferredStyle:UIAlertControllerStyleAlert
                                     completionBlock:^(UIAlertController *_Nonnull alertController, NSInteger index) {
            if (index != alertController.cancelButtonIndex) {
                [UIPasteboard generalPasteboard].string = text;
            }
        } cancelButtonTitle:@"OK" otherButtonTitles:@"COPY", nil] showUsingWindow:YES];
    });
#endif
    
#ifdef DEBUG
    //  abort();
#endif
}

@implementation LRExceptionUtil

+ (NSString *)takeBug {
    NSError *err;
    NSString *path = [LRExceptionUtil getBugReportPath];
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
        NSString *bugText = [[NSString alloc] initWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&err];
        if (![[NSFileManager defaultManager] removeItemAtPath:path error:&err]) {
        }
        return bugText;
    }
    return nil;
}

+ (NSString *)takeShareExtBug: (NSString *)groupIdentifier {
    NSError *err;
    NSURL *url = [LRCommonUtils getShareBugReportPath: groupIdentifier];
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:url.path]) {
        NSString *bugText = [[NSString alloc] initWithContentsOfURL:url encoding:NSUTF8StringEncoding error:&err];
        if (![[NSFileManager defaultManager] removeItemAtURL:url error:&err]) {
        }
        return bugText;
    }
    return nil;
}

+ (void)sendAssertionFailureHTTP:(NSString *)text reportUdid:(BOOL)reportUdid adaptiveConn:(BOOL)adaptiveConn {
    
}

+ (void)registerForUncaughtExceptionsAndSignals {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        LRPreviousUncaughtExceptionHandler = NSGetUncaughtExceptionHandler();
        /* Register for uncaught exceptions, signals */
        NSSetUncaughtExceptionHandler(&UncaughtExceptionHandler);
        SetupUncaughtSignals();
        // Ignore the signal SIGPIPE globally
        signal(SIGPIPE, SIG_IGN);
    });
}

+ (NSString *)getBugReportPath {
    NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *dir = paths[0];
    return [dir stringByAppendingPathComponent:@"bug.txt"];
}

+ (BOOL)previouslyCrashed {
    NSString *path = [LRExceptionUtil getBugReportPath];
    return [[NSFileManager defaultManager] fileExistsAtPath:path];
}

+ (void)writeExceptionBuffer:(NSString *)buffer {
    /*
     *  Get the error file to write this to
     */
    
    NSError *err;
    NSString *path = [LRExceptionUtil getBugReportPath];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [buffer writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&err];
    }
}

+ (void)writeStackTrace:(void **)frames length:(NSInteger)len intoString:(NSMutableString *)buffer {
    char **symbols = backtrace_symbols(frames, (int)len);
    
    NSMutableSet<NSString *> *modulesUsed = [[NSMutableSet alloc] init];
    for (NSInteger i = 0; i < len; ++i) {
        NSString *line = @(symbols[i]);
        NSMutableArray<NSString *> *fields = [[line componentsSeparatedByString:@" "] mutableCopy];
        [fields removeObject:@""];
        if (fields.count > 1) {
            NSString *module = fields[1];
            if (module) {  // not sure how this can be nil but it sometimes happens so don't recursively crash
                [modulesUsed addObject:module];
            }
        }
    }
    
    uintptr_t baseAddr = 0;
    NSMutableDictionary<NSString *, NSNumber *> *baseAddresses = [[NSMutableDictionary alloc] init];
    for (uint32_t j = 0;; j++) {
        const struct mach_header *mh = _dyld_get_image_header(j);
        if (!mh)
            break;
        NSString *name = @(_dyld_get_image_name(j));
        NSString *module = [name lastPathComponent];
        if ([module isEqualToString:[NSBundle mainBundle].infoDictionary[(NSString *)kCFBundleNameKey]]) {
            baseAddr = (uintptr_t)mh;
        }
        if ([modulesUsed containsObject:module]) {
            baseAddresses[module] = @((uintptr_t)mh);
        }
    }
    
    NSError *err;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:baseAddresses options:0 error:&err];
    if (!jsonData) {
        NSLog(@"Unable to jsonify object %@. Error: %@", baseAddresses, err);
    } else {
        [buffer appendFormat:@"Base addresses: %@\n",
         [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding]];
    }
    
    [buffer appendFormat:@"imo's Base address: 0x%08" PRIXPTR @"\n", baseAddr];
    [buffer appendString:@"Stack trace:\n\n"];
    for (NSInteger i = 0; i < len; ++i) {
        [buffer appendFormat:@"%4td - %s\n", i, symbols[i]];
    }
    free(symbols);
}

+ (void)writeRegistersWithContext:(void *)context intoString:(NSMutableString *)buffer {
#if !TARGET_IPHONE_SIMULATOR
    static const char *const registerNames[] =
#if defined(__LP64__)
    { "x0",  "x1",  "x2",  "x3",  "x4",  "x5",  "x6",  "x7",  "x8",  "x9",  "x10", "x11",
        "x12", "x13", "x14", "x15", "x16", "x17", "x18", "x19", "x20", "x21", "x22", "x23",
        "x24", "x25", "x26", "x27", "x28", "fp",  "lr",  "sp",  "pc",  "cpsr" };
#else
    { "r0",
        "r1",
        "r2",
        "r3",
        "r4",
        "r5",
        "r6",
        "r7",
        "r8",
        "r9",
        "r10",
        "r11",
        "r12",
        "sp",
        "lr",
        "pc",
        "cps"
        "r" };
#endif
    
    mcontext_t mctx = ((ucontext_t *)context)->uc_mcontext;
    _Static_assert(sizeof(registerNames) / sizeof(*registerNames) * sizeof(NSUInteger) == sizeof(mctx->__ss),
                   "wrong number of registers");
    const NSUInteger *registers = (const NSUInteger *)&mctx->__ss;
    
    [buffer appendString:@"Registers:\t"];
    for (NSInteger i = 0; i < sizeof(registerNames) / sizeof(*registerNames); i++) {
        [buffer appendFormat:@"%s: %tX\t", registerNames[i], registers[i]];
    }
    [buffer appendString:@"\n"];
#endif
}

// Send an exception report synchronously on a new thread
+ (NSDictionary *)buildExceptionReport:(NSString *)stackTrace {
    NSLog(@"ready to send exception report: %@", stackTrace);
    NSString *versionString = nil;
    NSRange versionPrefixRange = [stackTrace rangeOfString:@"imo version "];
    if (versionPrefixRange.location != NSNotFound) {
        NSUInteger versionStartIndex = versionPrefixRange.location + versionPrefixRange.length;
        NSRange newlineRange =
        [stackTrace rangeOfString:@"\n"
                          options:0
                            range:NSMakeRange(versionStartIndex, [stackTrace length] - versionStartIndex)];
        if (newlineRange.location != NSNotFound) {
            versionString = [stackTrace
                             substringWithRange:NSMakeRange(versionStartIndex, newlineRange.location - versionStartIndex)];
        }
    }
    if (!versionString) {
        // gr_assert2(versionString, stackTrace);
        NSString *version = [[NSBundle mainBundle].infoDictionary objectForKey:@"CFBundleShortVersionString"];
        versionString = version;
    }
    
    NSString *osString = nil;
    NSRange osPrefixRange = [stackTrace rangeOfString:@"iOS version "];
    if (osPrefixRange.location != NSNotFound) {
        NSUInteger osStartIndex = osPrefixRange.location + osPrefixRange.length;
        NSRange newlineRange = [stackTrace rangeOfString:@"\n"
                                                 options:0
                                                   range:NSMakeRange(osStartIndex, [stackTrace length] - osStartIndex)];
        if (newlineRange.location != NSNotFound) {
            NSUInteger osEndIndex = newlineRange.location;
            NSRange parenRange = [stackTrace rangeOfString:@" ("
                                                   options:0
                                                     range:NSMakeRange(osStartIndex, osEndIndex - osStartIndex)];
            if (parenRange.location != NSNotFound) {
                osEndIndex = parenRange.location;
            }
            osString = [stackTrace substringWithRange:NSMakeRange(osStartIndex, osEndIndex - osStartIndex)];
        }
    }
    if (!osString) {
        // gr_assert2(osString, stackTrace);
        osString = [UIDevice currentDevice].systemVersion;
    }
    
#if (TARGET_IPHONE_SIMULATOR)
    NSString *hardware = @"Simulator";
#else
    NSString *hardware = [LRCommonUtils getHardware];
#endif
    // Note: this is different from [Utils getUserAgent] because we use the version and OS from the saved crash report
    NSString *userAgentValue =
    [[NSString alloc] initWithFormat:@"imo%@/%@; (%@; U; iPhone OS %@)",
     @"iPhone",
     versionString,
     hardware,
     //[UIDevice currentDevice].systemName, // it may be iPhone OS or iOS
     osString];
    
    NSMutableDictionary *dict = [@{
        @"user_agent" : userAgentValue,
        @"stack_trace" : stackTrace
    } mutableCopy];
    return dict;
}

+ (void)reportBugIfPresent {
    NSString *bugText = [LRExceptionUtil takeBug];
    if (bugText) {
#if defined(DEBUG)
        [[UIAlertController alertControllerWithTitle:@"Error Report"
                                             message:bugText
                                      preferredStyle:UIAlertControllerStyleAlert
                                     completionBlock:^(UIAlertController *_Nonnull alertController, NSInteger index) {
            if (index != alertController.cancelButtonIndex) {
                [UIPasteboard generalPasteboard].string = bugText;
            }
        }
                                   cancelButtonTitle:@"OK"
                                   otherButtonTitles:@"COPY", nil] showUsingWindow:YES];
#endif
    }
}
@end
