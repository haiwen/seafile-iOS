//  SeafSdocDatePickerViewController.h
//  Date & time picker presented as a bottom sheet (centered card on iPad).
//  Replaces the action-sheet + "\n" padding hack, which had no popover
//  anchor and crashed on iPad.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^SeafSdocDatePickerCompletion)(NSDate *date);

@interface SeafSdocDatePickerViewController : UIViewController

- (instancetype)initWithTitle:(NSString *)title
                  initialDate:(nullable NSDate *)initialDate
                   completion:(SeafSdocDatePickerCompletion)completion;

@end

NS_ASSUME_NONNULL_END
