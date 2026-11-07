#import <UIKit/UIKit.h>

typedef struct {
    CGRect imageFrame;
    CGRect thumbnailsFrame;
    CGRect infoFrame;
} SeafPhotoInfoLayout;

/// Visible photo area above the thumbnail strip and toolbar.
NS_INLINE CGRect SeafPhotoBrowsingFrameMake(CGRect bounds, UIEdgeInsets insets) {
    CGRect safe = UIEdgeInsetsInsetRect(bounds, insets);
    return CGRectMake(CGRectGetMinX(safe), CGRectGetMinY(safe), MAX(0, safe.size.width),
                      MAX(0, safe.size.height - 44.0 - 45.0));
}

/// Shared by the gallery chrome and each photo page, including during folding.
NS_INLINE SeafPhotoInfoLayout SeafPhotoInfoLayoutMake(CGRect bounds, UIEdgeInsets insets) {
    CGRect safe = UIEdgeInsetsInsetRect(bounds, insets);
    CGFloat toolbarTop = MAX(CGRectGetMinY(safe), CGRectGetMaxY(safe) - 44.0);
    CGFloat stripHeight = MIN(45.0, toolbarTop - CGRectGetMinY(safe));
    CGFloat imageHeight = floor(MAX(0, toolbarTop - CGRectGetMinY(safe) - stripHeight) * 0.4);
    CGRect image = CGRectMake(CGRectGetMinX(safe), CGRectGetMinY(safe), MAX(0, safe.size.width), imageHeight);
    CGRect thumbnails = CGRectMake(image.origin.x, CGRectGetMaxY(image), image.size.width, stripHeight);
    CGRect info = CGRectMake(image.origin.x, CGRectGetMaxY(thumbnails), image.size.width,
                             MAX(0, toolbarTop - CGRectGetMaxY(thumbnails)));
    return (SeafPhotoInfoLayout){image, thumbnails, info};
}

@interface SeafPhotoInfoView : UIView

@property (nonatomic, strong, readonly) UIScrollView *infoScrollView;

- (instancetype)initWithFrame:(CGRect)frame;
- (void)clearExifDataView;
- (void)displayExifData:(NSData *)imageData;

/// Render metadata profile rows (from SeafSdocProfileAssembler) below standard info rows, above EXIF
- (void)renderProfileRows:(NSArray<NSDictionary *> *)rows;

/// Clear previously rendered profile rows
- (void)clearProfileRows;

/// Show a loading spinner in the profile section area while data is being fetched
- (void)showProfileLoading;

/// Hide the profile loading spinner
- (void)hideProfileLoading;

// Add convenience methods to access scroll view properties
- (CGPoint)contentOffset;
- (BOOL)isDragging;
- (UIPanGestureRecognizer *)panGestureRecognizer;

@end
