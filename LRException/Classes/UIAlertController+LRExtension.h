
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
typedef void(^completionBlock)(UIAlertController *alertController, NSInteger index);

@interface UIAlertController (LRExtension)
@property(nonatomic, assign) NSInteger cancelButtonIndex; // default -1 if no cancel button

+ (UIAlertController *)alertControllerWithTitle:(nullable NSString *)title
                                        message:(nullable NSString *)message
                                 preferredStyle:(UIAlertControllerStyle)preferredStyle
                                completionBlock:(nullable completionBlock)completionBlock
                              cancelButtonTitle:(nullable NSString *)cancelButtonTitle
                              otherButtonTitles:(nullable NSString *)otherButtonTitles, ... ;

- (void)show;

/*
 * @discussion
 * don't retain the alert as a property if you try to use this method to show.
 */
- (void)showUsingWindow:(BOOL)animated;
@end

NS_ASSUME_NONNULL_END
