//  SeafDocCommentInputView.h

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SeafDocCommentInputView : UIView

@property (nonatomic, strong, readonly) UIButton *photoButton;
@property (nonatomic, strong, readonly) UITextView *textView;
@property (nonatomic, strong, readonly) UIButton *sendButton;
@property (nonatomic, strong, readonly) UILabel *placeholderLabel;

@property (nonatomic, copy) void (^onTapPhoto)(void);
@property (nonatomic, copy) void (^onTapSend)(NSString * _Nonnull text);

- (void)setSendEnabled:(BOOL)enabled;
// Update placeholder visibility according to current content
- (void)updatePlaceholderVisibility;

@end

NS_ASSUME_NONNULL_END

