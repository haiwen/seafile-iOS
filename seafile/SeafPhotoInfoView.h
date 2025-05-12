#import <UIKit/UIKit.h>

@interface SeafPhotoInfoView : UIView

@property (nonatomic, strong, readonly) UIScrollView *infoScrollView;
@property (nonatomic, strong) NSDictionary *infoModel;

- (instancetype)initWithFrame:(CGRect)frame;
- (void)updateInfoView;
- (void)clearExifDataView;
- (void)displayExifData:(NSData *)imageData;

// Add convenience methods to access scroll view properties
- (CGPoint)contentOffset;
- (BOOL)isDragging;
- (UIPanGestureRecognizer *)panGestureRecognizer;

@end 