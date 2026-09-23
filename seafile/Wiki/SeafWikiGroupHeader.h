//
//  SeafWikiGroupHeader.h
//  seafilePro
//
//  Section header for the wiki home grid ("My Wikis", "Shared to me", group names).
//

#import <UIKit/UIKit.h>

@class SeafWikiGroup;

NS_ASSUME_NONNULL_BEGIN

@interface SeafWikiGroupHeader : UICollectionReusableView

@property (class, nonatomic, readonly) NSString *reuseIdentifier;

/// Total height of the header including the spacing the design puts above and below it.
@property (class, nonatomic, readonly) CGFloat headerHeight;

- (void)configureWithGroup:(SeafWikiGroup *)group;

@end

NS_ASSUME_NONNULL_END
