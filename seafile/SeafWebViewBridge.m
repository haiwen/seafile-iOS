//
//  SeafWebViewBridge.m
//  seafile
//
//  Shared JS Bridge components for WKWebView integration.
//

#import "SeafWebViewBridge.h"

#pragma mark - Bridge Script Constants

NSString * const SeafBridgeMessageName = @"callAndroidFunction";

NSString * const SeafBridgeShimScript =
@"(function(){\n"
"  var w=window;\n"
"  if(!w.WebViewJavascriptBridge){\n"
"    var _handlers={};\n"
"    w.WebViewJavascriptBridge={\n"
"      registerHandler:function(name,handler){ try{ _handlers[name]=handler; }catch(e){} },\n"
"      callHandler:function(name,data,resp){ try{ if(w.webkit && w.webkit.messageHandlers && w.webkit.messageHandlers[name]){ var payload=(typeof data==='string')?data:JSON.stringify(data||{}); w.webkit.messageHandlers[name].postMessage(payload); if(typeof resp==='function'){ resp(''); } } }catch(e){} },\n"
"      _invoke:function(name,data){ try{ var h=_handlers[name]; if(typeof h==='function'){ h(data, function(res){ try{ if(w.webkit && w.webkit.messageHandlers && w.webkit.messageHandlers.callAndroidFunction){ w.webkit.messageHandlers.callAndroidFunction.postMessage(JSON.stringify({action:'N_N_N_N_Callback',data:res||''})); } }catch(e){} }); } }catch(e){} }\n"
"    };\n"
"  }\n"
"})();";

NSString * const SeafBridgeHelperScript =
@"window.callAndroidFunction = window.callAndroidFunction || function(payload){ if(window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.callAndroidFunction){ window.webkit.messageHandlers.callAndroidFunction.postMessage(payload); } };";

#pragma mark - SeafWeakScriptMessageHandler

@implementation SeafWeakScriptMessageHandler

- (instancetype)initWithTarget:(id<WKScriptMessageHandler>)target
{
    if (self = [super init]) {
        _target = target;
    }
    return self;
}

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message
{
    [self.target userContentController:userContentController didReceiveScriptMessage:message];
}

@end

#pragma mark - WKUserContentController (SeafBridge)

@implementation WKUserContentController (SeafBridge)

- (void)seaf_injectBridgeScripts
{
    NSArray<NSString *> *scripts = @[SeafBridgeShimScript, SeafBridgeHelperScript];
    for (NSString *source in scripts) {
        WKUserScript *script = [[WKUserScript alloc] initWithSource:source
                                                      injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                                   forMainFrameOnly:YES];
        [self addUserScript:script];
    }
}

- (SeafWeakScriptMessageHandler *)seaf_addBridgeMessageHandlerWithTarget:(id<WKScriptMessageHandler>)target
{
    SeafWeakScriptMessageHandler *handler = [[SeafWeakScriptMessageHandler alloc] initWithTarget:target];
    [self addScriptMessageHandler:handler name:SeafBridgeMessageName];
    return handler;
}

- (void)seaf_removeBridgeMessageHandler
{
    [self removeScriptMessageHandlerForName:SeafBridgeMessageName];
}

@end
