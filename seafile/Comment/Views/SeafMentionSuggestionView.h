//  SeafMentionSuggestionView.h
//
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SeafMentionSuggestionView : UIView

@property (nonatomic, copy) void (^onSelectUser)(NSDictionary *user);

// Provide/refresh dataset (unfiltered)
- (void)updateAllUsers:(NSArray<NSDictionary *> *)users;

// Apply filter string (case-insensitive substring match against name/email)
- (void)applyFilter:(NSString * _Nullable)filter;

// Show/hide helpers
- (void)showInView:(UIView *)parent belowView:(UIView *)anchorView;
- (void)hide;

@end

NS_ASSUME_NONNULL_END



