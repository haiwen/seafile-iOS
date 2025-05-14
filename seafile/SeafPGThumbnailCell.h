#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class SeafPGThumbnailCellViewModel;

@interface SeafPGThumbnailCell : UICollectionViewCell

@property (nonatomic, strong, readonly) UIImageView *thumbnailImageView;
@property (nonatomic, strong, readonly) UIActivityIndicatorView *loadingIndicator;

- (void)configureWithViewModel:(SeafPGThumbnailCellViewModel *)viewModel;

@end

NS_ASSUME_NONNULL_END 