//
//  SeafWikiCell.h
//  seafilePro
//
//  Card cell for the wiki home grid. Laid out against the 260819 design spec.
//

#import <UIKit/UIKit.h>

@class SeafWikiInfo;

NS_ASSUME_NONNULL_BEGIN

@interface SeafWikiCell : UICollectionViewCell

@property (class, nonatomic, readonly) NSString *reuseIdentifier;

/// Fixed card height from the design spec; the width comes from the grid.
@property (class, nonatomic, readonly) CGFloat cardHeight;

/// Anchor for the iPad popover presented from the "more" button.
@property (nonatomic, strong, readonly) UIButton *moreButton;

@property (nonatomic, copy, nullable) void (^onMoreTapped)(void);

- (void)configureWithWiki:(SeafWikiInfo *)wiki;

@end

NS_ASSUME_NONNULL_END
