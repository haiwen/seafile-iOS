//  SeafDocCommentCell.h

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class SeafDocCommentItem;
@class SeafConnection;

@interface SeafDocCommentCell : UITableViewCell

@property (nonatomic, strong, readonly) UIImageView *avatarView;
@property (nonatomic, strong, readonly) UILabel *nameLabel;
@property (nonatomic, strong, readonly) UILabel *timeLabel;
@property (nonatomic, strong, readonly) UILabel *resolvedLabel;
@property (nonatomic, strong, readonly) UIImageView *resolvedImageView;
@property (nonatomic, strong, readonly) UIButton *moreButton;

- (void)configureWithItem:(SeafDocCommentItem *)item;
- (void)configureWithItem:(SeafDocCommentItem *)item connection:(SeafConnection * _Nullable)connection;

// Android-style: image tap callback
- (void)setImageTapHandler:(void(^)(NSString *imageURL))handler;

// Cancel unfinished image downloads in this cell (for close/reuse)
- (void)cancelLoading;

// Cancel all comment image downloads (class method, for VC shutdown)
+ (void)cancelAllImageLoads;

@end

NS_ASSUME_NONNULL_END

