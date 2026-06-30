//  SeafSdocLongTextEditorViewController.h
//  Align Android: LongTextSelectorActivity
//  Full-screen editor for long text (description) fields.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^SeafLongTextEditorCompletion)(NSString *key, NSString *text);

@interface SeafSdocLongTextEditorViewController : UIViewController

/// Designated initializer
/// @param key The metadata key (e.g. "_description")
/// @param title The display title for the navigation bar
/// @param text The initial text value
/// @param completion Called with the key and new text when the user taps Done
- (instancetype)initWithKey:(NSString *)key
                      title:(NSString *)title
                initialText:(nullable NSString *)text
                 completion:(SeafLongTextEditorCompletion)completion;

@end

NS_ASSUME_NONNULL_END
