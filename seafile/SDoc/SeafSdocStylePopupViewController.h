//
//  SeafSdocStylePopupViewController.h
//  seafilePro
//
//  Created by Henry on 2024/11/25.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@protocol SeafSdocStylePopupDelegate <NSObject>
- (void)didSelectStyle:(NSString *)style;
@end

@interface SeafSdocStylePopupViewController : UIViewController

@property (nonatomic, weak) id<SeafSdocStylePopupDelegate> delegate;
@property (nonatomic, copy) NSString *currentStyle;

@end

NS_ASSUME_NONNULL_END

