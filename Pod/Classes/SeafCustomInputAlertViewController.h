//
//  SeafCustomInputAlertViewController.h
//  Seafile
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SeafCustomInputAlertViewController : UIViewController

@property (nonatomic, copy) NSString *alertTitle;
@property (nonatomic, copy) NSString *placeholderText;
@property (nonatomic, copy) NSString *initialInputText;
@property (nonatomic, copy) void (^completionHandler)(NSString * _Nullable inputText);
@property (nonatomic, copy) void (^cancelHandler)(void);

- (instancetype)initWithTitle:(NSString *)title
                  placeholder:(NSString *)placeholder
                 initialInput:(nullable NSString *)initialInput
            completionHandler:(void (^)(NSString * _Nullable inputText))completionHandler
                cancelHandler:(nullable void (^)(void))cancelHandler;

- (void)presentOverViewController:(UIViewController *)presentingVC;

@end

NS_ASSUME_NONNULL_END 
