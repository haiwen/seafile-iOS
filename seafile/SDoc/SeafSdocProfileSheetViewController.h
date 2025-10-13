//  SeafSdocProfileSheetViewController.h

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SeafSdocProfileSheetViewController : UIViewController

// rows: array of dictionaries from SeafSdocProfileAssembler (title/icon/type/values)
- (instancetype)initWithRows:(NSArray<NSDictionary *> *)rows;

@end

NS_ASSUME_NONNULL_END

