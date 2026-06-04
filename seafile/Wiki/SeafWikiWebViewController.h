//
//  SeafWikiWebViewController.h
//  seafile
//
//  Created on 2026/5/12.
//

#import <UIKit/UIKit.h>
#import "SeafConnection.h"

NS_ASSUME_NONNULL_BEGIN

/// WebView controller for displaying wiki pages with authenticated session
@interface SeafWikiWebViewController : UIViewController

- (instancetype)initWithURL:(NSString *)urlString connection:(SeafConnection *)connection;
- (instancetype)initWithURL:(NSString *)urlString connection:(SeafConnection *)connection showSafariToolbar:(BOOL)showSafariToolbar wikiName:(nullable NSString *)wikiName;

@end

NS_ASSUME_NONNULL_END

