//
//  SeafGridCell.h
//  seafile
//

#import <UIKit/UIKit.h>
#import "Utils.h"

@class SeafFile;
@class SeafDir;
@class SeafUploadFile;

NS_ASSUME_NONNULL_BEGIN

@interface SeafGridCell : UICollectionViewCell

@property (nonatomic, strong, readonly) UIImageView *thumbnailView;
@property (nonatomic, strong) NSIndexPath *cellIndexPath;
@property (nonatomic, strong, nullable) SeafFile *cellSeafFile;
/// Upload entry this cell currently shows. Async icon callbacks must check it,
/// since an index path can be reassigned to a different upload before they land.
@property (nonatomic, strong, nullable) SeafUploadFile *cellUploadFile;
@property (nonatomic, assign) BOOL isUserEditing;

/// Preview aspect ratio (width / height). Currently 1:1 for a Files-like grid.
+ (CGFloat)thumbnailAspectRatio;

/// Title block height for the current Dynamic Type size (includes spacing above title).
+ (CGFloat)titleAreaHeight;

/// Preferred cell height for a given item width under the current content-size category.
+ (CGFloat)preferredItemHeightForWidth:(CGFloat)width;

- (void)configureWithDir:(SeafDir *)dir;
- (void)configureWithFile:(SeafFile *)file;
- (void)configureWithUploadFile:(SeafUploadFile *)file
                     completion:(void (^_Nullable)(UIImage * _Nullable image))completion;
- (void)updateDownloadStatusForFile:(SeafFile *)file waiting:(BOOL)waiting;
- (void)updateUploadProgress:(float)progress uploaded:(BOOL)uploaded filesize:(long long)filesize timestamp:(NSTimeInterval)timestamp;
- (void)resetCellFile;
- (void)updateCheckboxForSelected:(BOOL)selected;
/// Replace the preview image and lay it out for `style`: centered type icon, full-bleed
/// media (centered crop) or full-bleed document page (cropped from the top).
- (void)setThumbnailImage:(UIImage *)image style:(SeafThumbPreviewStyle)style;

@end

NS_ASSUME_NONNULL_END
