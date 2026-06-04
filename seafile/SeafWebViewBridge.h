//
//  SeafWebViewBridge.h
//  seafile
//
//  Shared JS Bridge components for WKWebView integration.
//  Used by both SDoc and Wiki WebView controllers to establish
//  a communication channel between the web page and the native app,
//  compatible with Android's JsBridge (lzyzsd/jsbridge) protocol.
//

#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Bridge Script Constants

/// Shim script that creates a `window.WebViewJavascriptBridge` object,
/// compatible with Android's BridgeWebView JS interface.
/// Provides `registerHandler`, `callHandler`, and `_invoke` methods.
FOUNDATION_EXPORT NSString * const SeafBridgeShimScript;

/// Helper script that creates a global `window.callAndroidFunction` function,
/// forwarding payloads to `webkit.messageHandlers.callAndroidFunction`.
FOUNDATION_EXPORT NSString * const SeafBridgeHelperScript;

/// The WKScriptMessageHandler name used for the bridge channel.
FOUNDATION_EXPORT NSString * const SeafBridgeMessageName;

#pragma mark - SeafWeakScriptMessageHandler

/// A weak-referencing wrapper for WKScriptMessageHandler to avoid retain cycles
/// between WKUserContentController and the view controller.
@interface SeafWeakScriptMessageHandler : NSObject <WKScriptMessageHandler>

@property (nonatomic, weak, readonly) id<WKScriptMessageHandler> target;

- (instancetype)initWithTarget:(id<WKScriptMessageHandler>)target;

@end

#pragma mark - WKUserContentController Helpers

/// Convenience methods for injecting bridge scripts into a WKUserContentController.
@interface WKUserContentController (SeafBridge)

/// Injects the bridge shim and helper scripts at document start.
- (void)seaf_injectBridgeScripts;

/// Registers a weak script message handler for the bridge channel.
/// Returns the created SeafWeakScriptMessageHandler (caller should keep a strong reference).
- (SeafWeakScriptMessageHandler *)seaf_addBridgeMessageHandlerWithTarget:(id<WKScriptMessageHandler>)target;

/// Removes the bridge message handler. Call this in dealloc.
- (void)seaf_removeBridgeMessageHandler;

@end

NS_ASSUME_NONNULL_END
