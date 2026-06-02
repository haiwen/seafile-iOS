//  SeafCollaboratorChipView.h
//  Reusable capsule view for collaborator display (avatar + name).
//  Used by both the profile sheet (via SeafCollaboratorChipCell) and the profile editor.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SeafCollaboratorChipView : UIView
- (void)configureWithName:(NSString *)name avatarURL:(NSString * _Nullable)avatarURL;
@end

NS_ASSUME_NONNULL_END
