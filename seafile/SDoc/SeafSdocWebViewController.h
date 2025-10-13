//  SeafSdocWebViewController.h
//  Seafile

#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

@class SeafFile;

NS_ASSUME_NONNULL_BEGIN

@interface SeafSdocWebViewController : UIViewController<WKNavigationDelegate, WKScriptMessageHandler>

@property (nonatomic, strong, readonly) SeafFile *file;

// Convenience initializer
- (instancetype)initWithFile:(SeafFile *)file fileName:(NSString *)fileName NS_DESIGNATED_INITIALIZER;

// Not available
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END

