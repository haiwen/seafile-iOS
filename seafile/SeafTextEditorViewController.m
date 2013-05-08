//
//  SeafTextEditorViewController.m
//  seafile
//
//  Created by Wang Wei on 4/9/13.
//  Copyright (c) 2013 Seafile Ltd.  All rights reserved.
//

#import "SeafTextEditorViewController.h"
#import "SeafAppDelegate.h"
#import "ExtentedString.h"
#import "Utils.h"
#import "Debug.h"

enum TOOL_ITEM {
    ITEM_BOLD = 0,
    ITEM_ITALIC,
    ITEM_STRIKE,
    ITEM_UNDERLINE,
    ITEM_UL,
    ITEM_OL,
    ITEM_LEFT,
    ITEM_CENTER,
    ITEM_RIGHT,
    ITEM_JUSTIFY,
};

@interface SeafTextEditorViewController ()
@property (nonatomic, retain) NSTimer *timer;
@property BOOL currentBoldStatus;
@property BOOL currentItalicStatus;
@property BOOL currentUnderlineStatus;

@property id<QLPreviewItem, PreViewDelegate> sfile;
@property int flags;
@end

@implementation SeafTextEditorViewController
@synthesize timer;
@synthesize currentBoldStatus;
@synthesize currentItalicStatus;
@synthesize currentUnderlineStatus;
@synthesize sfile;
@synthesize flags;

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (id) init
{
    return [self initWithNibName:(NSStringFromClass ([self class])) bundle:nil];
}

- (BOOL) IsSeaf
{
    return [sfile.mime isEqualToString:@"text/x-seafile"];
}

- (BOOL) IsMarkdown
{
    return IsIpad() && [sfile.mime isEqualToString:@"text/x-markdown"];
}

- (UIWebView *)webView
{
    return (UIWebView *)self.view;
}
- (void)bold2
{
    [self.webView stringByEvaluatingJavaScriptFromString:@"document.execCommand(\"Bold\")"];
}

- (void)italic2
{
    [self.webView stringByEvaluatingJavaScriptFromString:@"document.execCommand(\"Italic\")"];
}

- (void)underline2
{
    [self.webView stringByEvaluatingJavaScriptFromString:@"document.execCommand(\"Underline\")"];
}

- (void)btClicked:(NSString *)tag
{
    [self.webView stringByEvaluatingJavaScriptFromString:[NSString stringWithFormat:@"btClicked(\"%@\")", tag]];
    if (IsIpad() && [self IsSeaf]) {
        NSString *str = [self.webView stringByEvaluatingJavaScriptFromString:@"getBtState()"];
        [self handleUrl:str];
    }
}
- (void)bold
{
    [self btClicked:@"bold"];
}
- (void)italic
{
    [self btClicked:@"italic"];
}
- (void)insertLink
{
    [self btClicked:@"link"];
}
- (void)quote
{
    [self btClicked:@"quote"];
}
- (void)code
{
    [self btClicked:@"code"];
}
- (void)ol
{
    [self btClicked:@"olist"];
}
- (void)ul
{
    [self btClicked:@"ulist"];
}
- (void)heading
{
    [self btClicked:@"heading"];
}
- (void)hor
{
    [self btClicked:@"hr"];
}
- (void)undo
{
    [self btClicked:@"undo"];
}
- (void)redo
{
    [self btClicked:@"redo"];
}
- (void)help
{
    [self btClicked:@"help"];
}

- (void)strike
{
    [self btClicked:@"strike"];
}
- (void)underline
{
    [self btClicked:@"underline"];
}
- (void)indent
{
    [self btClicked:@"indent"];
}
- (void)outdent
{
    [self btClicked:@"outdent"];
}
- (void)left
{
    [self btClicked:@"left"];
}
- (void)center
{
    [self btClicked:@"center"];
}
- (void)right
{
    [self btClicked:@"right"];
}
- (void)justify
{
    [self btClicked:@"justify"];
}
- (void)removeLink
{
    [self btClicked:@"unlink"];
}
- (void)removeBar {
    // Locate non-UIWindow.
    UIWindow *keyboardWindow = nil;
    for (UIWindow *testWindow in [[UIApplication sharedApplication] windows]) {
        if (![[testWindow class] isEqual:[UIWindow class]]) {
            keyboardWindow = testWindow;
            break;
        }
    }

    // Locate UIWebFormView.
    for (UIView *possibleFormView in [keyboardWindow subviews]) {
        // iOS 5 sticks the UIWebFormView inside a UIPeripheralHostView.
        if ([[possibleFormView description] rangeOfString:@"UIPeripheralHostView"].location != NSNotFound) {
            for (UIView *subviewWhichIsPossibleFormView in [possibleFormView subviews]) {
                if ([[subviewWhichIsPossibleFormView description] rangeOfString:@"UIWebFormAccessory"].location != NSNotFound) {
                    [subviewWhichIsPossibleFormView removeFromSuperview];
                }
            }
        }
    }
}

- (void)keyboardWillShow:(NSNotification *)note
{
    [self performSelector:@selector(removeBar) withObject:nil afterDelay:0];
}

- (void)initSeafToolbar:(int)flag
{
    if (flag == flags)
        return;
    flags = flag;
    NSMutableArray *items = [[NSMutableArray alloc] init];
    UIBarButtonItem *item;
    item = [[UIBarButtonItem alloc] initWithTitle: @"rd" style:UIBarButtonItemStyleBordered target:self action:@selector(redo)];
    [items addObject:item];
    item = [[UIBarButtonItem alloc] initWithTitle: @"ud" style:UIBarButtonItemStyleBordered target:self action:@selector(undo)];
    [items addObject:item];
    item = [[UIBarButtonItem alloc] initWithTitle: @"uLk" style:UIBarButtonItemStyleBordered target:self action:@selector(removeLink)];
    [items addObject:item];
    item = [[UIBarButtonItem alloc] initWithTitle: @"Lk" style:UIBarButtonItemStyleBordered target:self action:@selector(insertLink)];
    [items addObject:item];
    if (flag & (1 << ITEM_JUSTIFY))
        item = [[UIBarButtonItem alloc] initWithTitle:@"-J" style:UIBarButtonItemStyleBordered target:self action:@selector(justify)];
    else
        item = [[UIBarButtonItem alloc] initWithTitle:@"J" style:UIBarButtonItemStyleBordered target:self action:@selector(justify)];
    [items addObject:item];
    if (flag & (1 << ITEM_RIGHT))
        item = [[UIBarButtonItem alloc] initWithTitle:@"-R" style:UIBarButtonItemStyleBordered target:self action:@selector(right)];
    else
        item = [[UIBarButtonItem alloc] initWithTitle:@"R" style:UIBarButtonItemStyleBordered target:self action:@selector(right)];
    [items addObject:item];
    if (flag & (1 << ITEM_CENTER))
        item = [[UIBarButtonItem alloc] initWithTitle:@"-C" style:UIBarButtonItemStyleBordered target:self action:@selector(center)];
    else
        item = [[UIBarButtonItem alloc] initWithTitle:@"C" style:UIBarButtonItemStyleBordered target:self action:@selector(center)];
    [items addObject:item];
    if (flag & (1 << ITEM_LEFT))
        item = [[UIBarButtonItem alloc] initWithTitle:@"-L" style:UIBarButtonItemStyleBordered target:self action:@selector(left)];
    else
        item = [[UIBarButtonItem alloc] initWithTitle:@"L" style:UIBarButtonItemStyleBordered target:self action:@selector(left)];
    [items addObject:item];
    item = [[UIBarButtonItem alloc] initWithTitle: @"Out" style:UIBarButtonItemStyleBordered target:self action:@selector(outdent)];
    [items addObject:item];
    item = [[UIBarButtonItem alloc] initWithTitle: @"In" style:UIBarButtonItemStyleBordered target:self action:@selector(indent)];
    [items addObject:item];
    if (flag & (1 << ITEM_OL))
        item = [[UIBarButtonItem alloc] initWithTitle: @"-ol" style:UIBarButtonItemStyleBordered target:self action:@selector(ol)];
    else
        item = [[UIBarButtonItem alloc] initWithTitle: @"ol" style:UIBarButtonItemStyleBordered target:self action:@selector(ol)];
    [items addObject:item];
    if (flag & (1 << ITEM_UL))
        item = [[UIBarButtonItem alloc] initWithTitle: @"-ul" style:UIBarButtonItemStyleBordered target:self action:@selector(ul)];
    else
        item = [[UIBarButtonItem alloc] initWithTitle: @"ul" style:UIBarButtonItemStyleBordered target:self action:@selector(ul)];
    [items addObject:item];
    if (flag & (1 << ITEM_UNDERLINE))
        item = [[UIBarButtonItem alloc] initWithTitle:@"-U" style:UIBarButtonItemStyleBordered target:self action:@selector(underline)];
    else
        item = [[UIBarButtonItem alloc] initWithTitle:@"U" style:UIBarButtonItemStyleBordered target:self action:@selector(underline)];
    [items addObject:item];
    if (flag & (1 << ITEM_STRIKE))
        item = [[UIBarButtonItem alloc] initWithTitle:@"-S" style:UIBarButtonItemStyleBordered target:self action:@selector(strike)];
    else
        item = [[UIBarButtonItem alloc] initWithTitle:@"S" style:UIBarButtonItemStyleBordered target:self action:@selector(strike)];
    [items addObject:item];
    if (flag & (1 << ITEM_ITALIC))
        item= [[UIBarButtonItem alloc] initWithTitle:@"-I" style:UIBarButtonItemStyleBordered target:self action:@selector(italic)];
    else
        item= [[UIBarButtonItem alloc] initWithTitle:@"I" style:UIBarButtonItemStyleBordered target:self action:@selector(italic)];
    [items addObject:item];
    if (flag & (1 << ITEM_BOLD))
        item = [[UIBarButtonItem alloc] initWithTitle:@"-B" style:UIBarButtonItemStyleBordered target:self action:@selector(bold)];
    else
        item = [[UIBarButtonItem alloc] initWithTitle:@"B" style:UIBarButtonItemStyleBordered target:self action:@selector(bold)];
    [items addObject:item];
    self.navigationItem.rightBarButtonItems = items;
}

- (void)checkBtState:(id)sender
{
    if (IsIpad() && [self IsSeaf]) {
        NSString *str = [self.webView stringByEvaluatingJavaScriptFromString:@"getBtState()"];
        [self handleUrl:str];
    }
}

- (void)checkSelection:(id)sender
{
    if ([self IsSeaf]) {
        if (!IsIpad()) {
            BOOL boldEnabled = [[self.webView stringByEvaluatingJavaScriptFromString:@"document.queryCommandState('Bold')"] boolValue];
            BOOL italicEnabled = [[self.webView stringByEvaluatingJavaScriptFromString:@"document.queryCommandState('Italic')"] boolValue];
            BOOL underlineEnabled = [[self.webView stringByEvaluatingJavaScriptFromString:@"document.queryCommandState('Underline')"] boolValue];

            NSMutableArray *items = [[NSMutableArray alloc] init];

            UIBarButtonItem *bold = [[UIBarButtonItem alloc] initWithTitle:(boldEnabled) ? @"[B]" : @"B" style:UIBarButtonItemStyleBordered target:self action:@selector(bold2)];
            UIBarButtonItem *italic = [[UIBarButtonItem alloc] initWithTitle:(italicEnabled) ? @"[I]" : @"I" style:UIBarButtonItemStyleBordered target:self action:@selector(italic2)];
            UIBarButtonItem *underline = [[UIBarButtonItem alloc] initWithTitle:(underlineEnabled) ? @"[U]" : @"U" style:UIBarButtonItemStyleBordered target:self action:@selector(underline2)];

            [items addObject:underline];
            [items addObject:italic];
            [items addObject:bold];

            if (currentBoldStatus != boldEnabled || currentItalicStatus != italicEnabled || currentUnderlineStatus != underlineEnabled || sender == self) {
                self.navigationItem.rightBarButtonItems = items;
                currentBoldStatus = boldEnabled;
                currentItalicStatus = italicEnabled;
                currentUnderlineStatus = underlineEnabled;
            }
        } else {
            [self initSeafToolbar:0];
        }
    } else if ([self IsMarkdown]) {
        NSMutableArray *items = [[NSMutableArray alloc] init];
        UIBarButtonItem *bold = [[UIBarButtonItem alloc] initWithTitle:@"B" style:UIBarButtonItemStyleBordered target:self action:@selector(bold)];
        UIBarButtonItem *italic = [[UIBarButtonItem alloc] initWithTitle:@"I" style:UIBarButtonItemStyleBordered target:self action:@selector(italic)];
        UIBarButtonItem *link = [[UIBarButtonItem alloc] initWithTitle: @"Link" style:UIBarButtonItemStyleBordered target:self action:@selector(insertLink)];
        UIBarButtonItem *quote = [[UIBarButtonItem alloc] initWithTitle: @"Quote" style:UIBarButtonItemStyleBordered target:self action:@selector(quote)];
        UIBarButtonItem *code = [[UIBarButtonItem alloc] initWithTitle: @"Code" style:UIBarButtonItemStyleBordered target:self action:@selector(code)];
        UIBarButtonItem *pic = [[UIBarButtonItem alloc] initWithTitle: @"Pic" style:UIBarButtonItemStyleBordered target:self action:@selector(pic)];
        UIBarButtonItem *ol = [[UIBarButtonItem alloc] initWithTitle: @"ol" style:UIBarButtonItemStyleBordered target:self action:@selector(ol)];
        UIBarButtonItem *ul = [[UIBarButtonItem alloc] initWithTitle: @"ul" style:UIBarButtonItemStyleBordered target:self action:@selector(ul)];
        UIBarButtonItem *heading = [[UIBarButtonItem alloc] initWithTitle: @"heading" style:UIBarButtonItemStyleBordered target:self action:@selector(heading)];
        UIBarButtonItem *hor = [[UIBarButtonItem alloc] initWithTitle: @"hr" style:UIBarButtonItemStyleBordered target:self action:@selector(hor)];
        UIBarButtonItem *undo = [[UIBarButtonItem alloc] initWithTitle: @"undo" style:UIBarButtonItemStyleBordered target:self action:@selector(undo)];
        UIBarButtonItem *redo = [[UIBarButtonItem alloc] initWithTitle: @"redo" style:UIBarButtonItemStyleBordered target:self action:@selector(redo)];
        UIBarButtonItem *help = [[UIBarButtonItem alloc] initWithTitle: @"?" style:UIBarButtonItemStyleBordered target:self action:@selector(redo)];
        [items addObject:help];
        [items addObject:redo];
        [items addObject:undo];
        [items addObject:hor];
        [items addObject:heading];
        [items addObject:ul];
        [items addObject:ol];
        [items addObject:pic];
        [items addObject:code];
        [items addObject:quote];
        [items addObject:link];
        [items addObject:italic];
        [items addObject:bold];

        self.navigationItem.rightBarButtonItems = items;
    } else {
        self.navigationItem.rightBarButtonItems = nil;
    }
}

- (void)cancel
{
    [self.navigationController dismissViewControllerAnimated:NO completion:nil];
}

- (void)save
{
    NSString *content = [self.webView stringByEvaluatingJavaScriptFromString:@"getContent()"];
    [sfile saveContent:content];
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    [appdelegate.detailVC refreshView];
    [appdelegate.masterVC refreshView];
    [appdelegate.starredVC refreshView];
    [self.navigationController dismissViewControllerAnimated:NO completion:nil];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view from its nib.
    self.flags = -1;
    [self checkSelection:self];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
    NSMutableArray *litems = [[NSMutableArray alloc] init];
    UIBarButtonItem *cancelItem = [[UIBarButtonItem alloc] initWithTitle:@"Cancel" style:UIBarButtonItemStyleBordered target:self action:@selector(cancel)];
    UIBarButtonItem *saveItem = [[UIBarButtonItem alloc] initWithTitle:@"Save" style:UIBarButtonItemStyleBordered target:self action:@selector(save)];
    [litems addObject:cancelItem];
    [litems addObject:saveItem];
    self.navigationItem.leftBarButtonItems = litems;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

# pragma - UIWebViewDelegate
- (void)webViewDidFinishLoad:(UIWebView *)webView
{
    NSString *js = [NSString stringWithFormat:@"setContent(\"%@\");", [sfile.content stringEscapedForJavasacript]];
    Debug("content=%@\n", [sfile.content stringEscapedForJavasacript]);
    [self.webView stringByEvaluatingJavaScriptFromString:js];
}
- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error
{
    Debug("...");
}

- (BOOL)handleUrl:(NSString *)urlStr
{
    //Decode the url string
    urlStr = [urlStr stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    NSError *jsonError;
    //parse JSON input in the URL
    NSDictionary *callInfo = [NSJSONSerialization
                              JSONObjectWithData:[urlStr dataUsingEncoding:NSUTF8StringEncoding]
                              options:kNilOptions
                              error:&jsonError];
    //check if there was error in parsing JSON input
    if (jsonError != nil) {
        Debug("Error parsing JSON for the url %@", urlStr);
        return NO;
    }

    //Get function name. It is a required input
    NSString *functionName = [callInfo objectForKey:@"functionname"];
    if (functionName == nil) {
        Debug("Missing function name");
        return NO;
    }
    NSArray *argsArray = [callInfo objectForKey:@"args"];
    int flag = 0;
    for (NSString *s in argsArray) {
        if ([@"bold" isEqualToString:s])
            flag |= 1 << ITEM_BOLD;
        else if ([@"italic" isEqualToString:s])
            flag |= 1 << ITEM_ITALIC;
        else if ([@"strikethrough" isEqualToString:s])
            flag |= 1 << ITEM_STRIKE;
        else if ([@"underline" isEqualToString:s])
            flag |= 1 << ITEM_UNDERLINE;
        else if ([@"insertunorderedlist" isEqualToString:s])
            flag |= 1 << ITEM_UL;
        else if ([@"insertorderedlist" isEqualToString:s])
            flag |= 1 << ITEM_OL;
        else if ([@"justifyleft" isEqualToString:s])
            flag |= 1 << ITEM_LEFT;
        else if ([@"justifycenter" isEqualToString:s])
            flag |= 1 << ITEM_CENTER;
        else if ([@"justifyright" isEqualToString:s])
            flag |= 1 << ITEM_RIGHT;
        else if ([@"justifyfull" isEqualToString:s])
            flag |= 1 << ITEM_JUSTIFY;
    }
    //Debug("args=%@, flag=%x\n", argsArray, flag);
    [self initSeafToolbar:flag];
    return NO;
}
- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType
{
    NSString *urlStr = request.URL.absoluteString;
    NSString *protocolPrefix = @"js2ios://";
    if ([[urlStr lowercaseString] hasPrefix:protocolPrefix]) {
        urlStr = [urlStr substringFromIndex:protocolPrefix.length];
        return [self handleUrl:urlStr];
    }
    return YES;
}

- (void)setFile:(id<QLPreviewItem, PreViewDelegate>) file
{
    self.sfile = file;
    NSString *path;
    if ([self IsMarkdown])
        path = [[NSBundle mainBundle] pathForResource:@"edit_file_md" ofType:@"html"];
    else if ([self IsSeaf]) {
        if (IsIpad()) {
            path = [[NSBundle mainBundle] pathForResource:@"edit_file_seaf2" ofType:@"html"];
            timer = [NSTimer scheduledTimerWithTimeInterval:0.1 target:self selector:@selector(checkBtState:) userInfo:nil repeats:YES];
        } else {
            path = [[NSBundle mainBundle] pathForResource:@"edit_file_seaf" ofType:@"html"];
            timer = [NSTimer scheduledTimerWithTimeInterval:0.1 target:self selector:@selector(checkSelection:) userInfo:nil repeats:YES];
        }
    } else
        path = [[NSBundle mainBundle] pathForResource:@"edit_file_text" ofType:@"html"];

    NSURL *url = [NSURL fileURLWithPath:path];
    NSURLRequest *request = [[NSURLRequest alloc] initWithURL:url.previewItemURL cachePolicy: NSURLRequestUseProtocolCachePolicy timeoutInterval: 1];
    [(UIWebView *)self.view loadRequest: request];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    if (!IsIpad()) {
        return (interfaceOrientation == UIInterfaceOrientationPortrait);
    } else if ([self IsMarkdown])
        return (interfaceOrientation == UIInterfaceOrientationLandscapeLeft) || (interfaceOrientation == UIInterfaceOrientationLandscapeRight);
    else
        return YES;
}

@end
