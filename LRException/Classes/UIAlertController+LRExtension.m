
#import "UIAlertController+LRExtension.h"
#import <objc/runtime.h>

@interface UIViewController (Top)

@end

@implementation UIViewController (Top)

+ (UIViewController *)topVisibleViewController {
    UIViewController *rootViewController = [UIApplication sharedApplication].delegate.window.rootViewController;
    UIViewController *visibleViewController = [rootViewController topVisibleViewController];
    return visibleViewController;
}

- (UIViewController *)topVisibleViewController {
    if (self.presentedViewController) {
        return [self.presentedViewController topVisibleViewController];
    }
    
    if ([self isKindOfClass:[UINavigationController class]]) {
        return [((UINavigationController *)self).topViewController topVisibleViewController];
    }
    
    if ([self isKindOfClass:[UITabBarController class]]) {
        return [((UITabBarController *)self).selectedViewController topVisibleViewController];
    }
    
    if ([self isViewLoaded] && self.view.window) {
        return self;
    } else {
        return nil;
    }
}

@end

static void* cancelButtonIndexKey = &cancelButtonIndexKey;

@interface UIAlertController (Private)

@property (nonatomic, strong) UIWindow *alertWindow;

@end

@implementation UIAlertController (Private)

@dynamic alertWindow;

- (void)setAlertWindow:(UIWindow *)alertWindow {
    objc_setAssociatedObject(self, @selector(alertWindow), alertWindow, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (UIWindow *)alertWindow {
    return objc_getAssociatedObject(self, @selector(alertWindow));
}

@end

@implementation UIAlertController (LRExtension)
+ (UIAlertController *)alertControllerWithTitle:(nullable NSString *)title
                                        message:(nullable NSString *)message
                                 preferredStyle:(UIAlertControllerStyle)preferredStyle
                                completionBlock:(nullable completionBlock)completionBlock
                              cancelButtonTitle:(nullable NSString *)cancelButtonTitle
                              otherButtonTitles:(nullable NSString *)otherButtonTitles, ... {
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:preferredStyle];
    alertController.cancelButtonIndex = -1;
    
    if (cancelButtonTitle.length) {
        __weak typeof(alertController) weakAlert = alertController;
        UIAlertAction * cancelAction = [UIAlertAction actionWithTitle:cancelButtonTitle style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
            __strong typeof(weakAlert) strongAlert = weakAlert;
            if (completionBlock) {
                completionBlock(strongAlert ,0);
            }
        }];
        alertController.cancelButtonIndex = 0;
        [alertController addAction:cancelAction];
    }
    
    NSInteger index = cancelButtonTitle.length > 0 ? 1 : 0;
    
    va_list argumentList;
    va_start(argumentList, otherButtonTitles);
    for (id eachObject = otherButtonTitles; eachObject; eachObject = va_arg(argumentList, id)) {
        __weak typeof(alertController) weakAlert = alertController;
        UIAlertAction * otherAction = [UIAlertAction actionWithTitle:eachObject style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            __strong typeof(weakAlert) strongAlert = weakAlert;
            if (completionBlock) {
                completionBlock(strongAlert, index);
            }
        }];
        [alertController addAction:otherAction];
        
        index++;
    }
    va_end(argumentList);
    
    return alertController;
}

- (void)show {
    UIViewController *top = [UIViewController topVisibleViewController];
    if (top) {
        [top presentViewController:self animated:YES completion:nil];
    }
}

/*
 * https://stackoverflow.com/questions/26554894/how-to-present-uialertcontroller-when-not-in-a-view-controller
 */
- (void)showUsingWindow:(BOOL)animated {
    self.alertWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.alertWindow.rootViewController = [[UIViewController alloc] init];
    
    id<UIApplicationDelegate> delegate = [UIApplication sharedApplication].delegate;
    // Applications that does not load with UIMainStoryboardFile might not have a window property:
    if ([delegate respondsToSelector:@selector(window)]) {
        // we inherit the main window's tintColor
        self.alertWindow.tintColor = delegate.window.tintColor;
    }
    
    // window level is above the top window (this makes the alert, if it's a sheet, show over the keyboard)
    UIWindow *topWindow = [UIApplication sharedApplication].windows.lastObject;
    self.alertWindow.windowLevel = topWindow.windowLevel + 1;
    
    [self.alertWindow makeKeyAndVisible];
    [self.alertWindow.rootViewController presentViewController:self animated:animated completion:nil];
}

- (void)setCancelButtonIndex:(NSInteger)cancelButtonIndex {
    objc_setAssociatedObject(self, cancelButtonIndexKey, @(cancelButtonIndex), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (NSInteger)cancelButtonIndex {
    return [(NSNumber *)objc_getAssociatedObject(self, cancelButtonIndexKey) integerValue];
}
@end
