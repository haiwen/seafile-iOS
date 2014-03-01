var g_args=""
var g_last_url=""
function openCustomURLinIFrame(src) {
    var rootElm = document.documentElement;
    var newFrameElm = document.createElement("IFRAME");
    newFrameElm.setAttribute("src", src);
    rootElm.appendChild(newFrameElm);
    //remove the frame now
    newFrameElm.parentNode.removeChild(newFrameElm);
}
function a(src) {
    var s = document.createElement('script');
    s.type = 'text/javascript';
    s.async = true;
    s.src = src;
    var rootElm = document.documentElement;
    rootElm.appendChild(s);
}
function calliOSFunction(functionName, args, successCallback, errorCallback) {
    var url = "js2ios://";
    var callInfo = {};
    callInfo.functionname = functionName;
    if (successCallback) {
        callInfo.success = successCallback;
    }
    if (errorCallback) {
        callInfo.error = errorCallback;
    }
    if (args) {
        callInfo.args = args;
    }
    g_args = JSON.stringify(callInfo)
    console.log(g_args)
    url += JSON.stringify(callInfo)
    if (g_last_url != url) {
        g_last_url = url;
        openCustomURLinIFrame(url);
    }
}

function getBtState () {
    console.log(g_args)
    return g_args
}
