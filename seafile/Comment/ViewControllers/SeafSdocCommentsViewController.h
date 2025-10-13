//  SeafSdocCommentsViewController.h

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class SDocPageOptionsModel;
@class SeafConnection;

@interface SeafSdocCommentsViewController : UIViewController

// Required: pass from SDoc page
@property (nonatomic, strong) SDocPageOptionsModel *pageOptions;
@property (nonatomic, copy) NSString *docDisplayName; // optional title shown on nav bar

// SeafConnection for authenticated requests (optional, but recommended for image loading)
@property (nonatomic, weak) SeafConnection *connection;

@end

NS_ASSUME_NONNULL_END

