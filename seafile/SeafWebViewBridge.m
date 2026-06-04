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
"    var _callbacks={};\n"
"    var _cbId=0;\n"
"    w.WebViewJavascriptBridge={\n"
"      registerHandler:function(name,handler){ try{ _handlers[name]=handler; }catch(e){} },\n"
"      callHandler:function(name,data,resp){ try{ if(w.webkit && w.webkit.messageHandlers && w.webkit.messageHandlers[name]){ var payload=(typeof data==='string')?data:JSON.stringify(data||{}); var registered=false; if(typeof resp==='function'){ var obj=null; try{ obj=JSON.parse(payload); }catch(e){} if(obj && typeof obj==='object'){ _cbId++; _callbacks[_cbId]=resp; obj.__cbId=_cbId; payload=JSON.stringify(obj); registered=true; } } w.webkit.messageHandlers[name].postMessage(payload); if(typeof resp==='function' && !registered){ resp(''); } } }catch(e){} },\n"
"      _handleResponse:function(id,data){ try{ var cb=_callbacks[id]; delete _callbacks[id]; if(typeof cb==='function'){ cb(data); } }catch(e){} },\n"
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

#pragma mark - WKWebView (SeafBridge)

@implementation WKWebView (SeafBridge)

- (void)seaf_sendBridgeResponse:(NSString *)data forCallbackId:(id)callbackId
{
    if (data.length == 0) return;

    long long cbId = 0;
    if ([callbackId isKindOfClass:[NSNumber class]]) {
        cbId = [(NSNumber *)callbackId longLongValue];
    } else if ([callbackId isKindOfClass:[NSString class]]) {
        cbId = [(NSString *)callbackId longLongValue];
    }
    if (cbId <= 0) return;

    // Array-wrap so NSJSONSerialization escapes the string; JS unwraps with [0].
    NSData *encoded = [NSJSONSerialization dataWithJSONObject:@[data] options:0 error:nil];
    NSString *jsonArray = [[NSString alloc] initWithData:encoded encoding:NSUTF8StringEncoding];
    if (!jsonArray) return;

    NSString *js = [NSString stringWithFormat:
                    @"window.WebViewJavascriptBridge && window.WebViewJavascriptBridge._handleResponse(%lld, %@[0]);",
                    cbId, jsonArray];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self evaluateJavaScript:js completionHandler:nil];
    });
}

@end
