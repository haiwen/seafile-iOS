//  SeafMentionSheetViewController.h
//
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SeafMentionSheetViewController : UIViewController

@property (nonatomic, copy) void (^onSelectUser)(NSDictionary *user);

- (void)updateAllUsers:(NSArray<NSDictionary *> *)users;
- (void)applyFilter:(NSString * _Nullable)filter;

@end

NS_ASSUME_NONNULL_END


