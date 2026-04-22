#import <UIKit/UIKit.h>

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