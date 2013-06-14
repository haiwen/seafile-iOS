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
    ITEM_REDO = 0,
    ITEM_UNDO,
    ITEM_JUSTIFY,
    ITEM_RIGHT,
    ITEM_CENTER,
    ITEM_LEFT,
    ITEM_OUDENT,
    ITEM_INDENT,
    ITEM_OL,
    ITEM_UL,
    ITEM_UNDERLINE,
    ITEM_STRIKE,
    ITEM_ITALIC,
    ITEM_BOLD,
    ITEM_MAX,
};

@interface SeafTextEditorViewController ()
@property (nonatomic, retain) NSTimer *timer;
@property BOOL currentBoldStatus;
@property BOOL currentItalicStatus;
@property BOOL currentUnderlineStatus;
@property UIBarButtonItem *ep;

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
@synthesize ep;

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

- (void)edit_preview
{
    NSString *ret = [self.webView stringByEvaluatingJavaScriptFromString:@"toggle_ep()"];
    if ([ret isEqualToString:@"1"]) {
        ep.title = @"Edit";
    } else {
        ep.title = @"Preview";
    }
}
- (void)pound
{
    [self btClicked:@"pound"];
}
- (void)asterisk
{
    [self btClicked:@"star"];
}
- (void)equal
{
    [self btClicked:@"equal"];
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
- (void)image
{
    [self btClicked:@"image"];
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

- (UIBarButtonItem *)getBarItem:(NSString *)imageName action:(SEL)action active:(int)active
{
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame = CGRectMake(0,0,20,20);
    UIImage *img = [UIImage imageNamed:[NSString stringWithFormat:@"%@.png", imageName]];
    UIImage *img2 = [UIImage imageNamed:[NSString stringWithFormat:@"%@2.png", imageName]];
    [btn setImage:img forState:UIControlStateNormal];
    [btn setImage:img2 forState:UIControlStateSelected];

    if(active)
        btn.selected = YES;
    [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithCustomView:btn];
    return item;
}

- (UIBarButtonItem *)getTextBarItem:(NSString *)title action:(SEL)action active:(int)active
{
    UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithTitle:title style:UIBarButtonItemStyleBordered target:self action:action];
    return item;
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
- (void)addItem:(UIBarButtonItem *)item to:(NSMutableArray *)items
{
    UIBarButtonItem *space = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace target:self action:nil];
    space.width = 16.0;
    [items addObject:item];
    [items addObject:space];
}
- (void)updateSeafToolbar:(int)flag
{
    if (flag == flags)
        return;
    flags = flag;
    for (int i = 0; i < ITEM_MAX; ++i) {
        UIBarButtonItem *item = [self.navigationItem.rightBarButtonItems objectAtIndex:2*i];
        UIButton *btn = (UIButton *)item.customView;
        btn.selected = (flag & (1 << i)) != 0;
    }
}

- (void)initSeafToolbar:(int)flag
{
    flags = flag;
    NSMutableArray *items = [[NSMutableArray alloc] init];
    UIBarButtonItem *item;

    item = [self getBarItem:@"bt-redo" action:@selector(redo) active:0];
    [self addItem:item to:items];
    item = [self getBarItem:@"bt-undo" action:@selector(undo) active:0];
    [self addItem:item to:items];
    item = [self getBarItem:@"bt-justify" action:@selector(justify) active:flag & (1 << ITEM_JUSTIFY)];
    [self addItem:item to:items];
    item = [self getBarItem:@"bt-right" action:@selector(right) active:flag & (1 << ITEM_RIGHT)];
    [self addItem:item to:items];
    item = [self getBarItem:@"bt-center" action:@selector(center) active:flag & (1 << ITEM_CENTER)];
    [self addItem:item to:items];
    item = [self getBarItem:@"bt-left" action:@selector(left) active:flag & (1 << ITEM_LEFT)];
    [self addItem:item to:items];
    item = [self getBarItem:@"bt-outdent" action:@selector(outdent) active:0];
    [self addItem:item to:items];
    item = [self getBarItem:@"bt-indent" action:@selector(indent) active:0];
    [self addItem:item to:items];
    item = [self getBarItem:@"bt-ol" action:@selector(ol) active:flag & (1 << ITEM_OL)];
    [self addItem:item to:items];
    item = [self getBarItem:@"bt-ul" action:@selector(ul) active:flag & (1 << ITEM_UL)];
    [self addItem:item to:items];
    item = [self getBarItem:@"bt-underline" action:@selector(underline) active:flag & (1 << ITEM_UNDERLINE)];
    [self addItem:item to:items];
    item = [self getBarItem:@"bt-strikethrough" action:@selector(strike) active:flag & (1 << ITEM_STRIKE)];
    [self addItem:item to:items];
    item = [self getBarItem:@"bt-italic" action:@selector(italic) active:flag & (1 << ITEM_ITALIC)];
    [self addItem:item to:items];
    item = [self getBarItem:@"bt-bold" action:@selector(bold) active:flag & (1 << ITEM_BOLD)];
    [self addItem:item to:items];
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
        UIBarButtonItem *pound = [self getBarItem:@"bt-pound" action:@selector(pound) active:0];
        UIBarButtonItem *asterisk = [self getBarItem:@"bt-asterisk" action:@selector(asterisk) active:0];
        UIBarButtonItem *equal = [self getBarItem:@"bt-equal" action:@selector(equal) active:0];
        UIBarButtonItem *bold = [self getBarItem:@"bt-bold" action:@selector(bold) active:0];
        UIBarButtonItem *italic = [self getBarItem:@"bt-italic" action:@selector(italic) active:0];
        UIBarButtonItem *link = [self getBarItem:@"bt-link" action:@selector(insertLink) active:0];
        UIBarButtonItem *quote = [self getBarItem:@"bt-quote" action:@selector(quote) active:0];
        UIBarButtonItem *code = [self getBarItem:@"bt-code" action:@selector(code) active:0];
        UIBarButtonItem *img = [self getBarItem:@"bt-image" action:@selector(image) active:0];
        UIBarButtonItem *ol = [self getBarItem:@"bt-ol" action:@selector(ol) active:0];
        UIBarButtonItem *ul = [self getBarItem:@"bt-ul" action:@selector(ul) active:0];
        //UIBarButtonItem *heading = [self getBarItem:@"bt-heading" action:@selector(heading) active:0];
        //UIBarButtonItem *hor = [self getBarItem:@"bt-hor" action:@selector(hor) active:0];
        UIBarButtonItem *undo = [self getBarItem:@"bt-undo" action:@selector(undo) active:0];
        UIBarButtonItem *redo = [self getBarItem:@"bt-redo" action:@selector(redo) active:0];
        UIBarButtonItem *help = [self getBarItem:@"bt-help" action:@selector(help) active:0];
        [self addItem:help to:items];
        [self addItem:redo to:items];
        [self addItem:undo to:items];
        //[self addItem:hor to:items];
        //[self addItem:heading to:items];
        [self addItem:ul to:items];
        [self addItem:ol to:items];
        [self addItem:img to:items];
        [self addItem:code to:items];
        [self addItem:quote to:items];
        [self addItem:link to:items];
        [self addItem:italic to:items];
        [self addItem:bold to:items];
        [self addItem:equal to:items];
        [self addItem:asterisk to:items];
        [self addItem:pound to:items];

        self.navigationItem.rightBarButtonItems = items;
    } else {
        self.navigationItem.rightBarButtonItems = nil;
    }
}
- (void)dismissCurrentView
{
    [self.navigationController dismissViewControllerAnimated:NO completion:nil];
}
- (void)cancel
{
    [self dismissCurrentView];
}

- (void)save
{
    NSString *content = [self.webView stringByEvaluatingJavaScriptFromString:@"getContent()"];
    [sfile saveContent:content];
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    [self.detailViewController refreshView];
    [appdelegate.fileVC refreshView];
    [appdelegate.starredVC refreshView];
    [self dismissCurrentView];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view from its nib.
    self.flags = -1;
    self.navigationItem.rightBarButtonItems = nil;
    [self checkSelection:self];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
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
    [self.webView stringByEvaluatingJavaScriptFromString:js];
}
- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error
{
}

- (BOOL)handleUrl:(NSString *)urlStr
{
    //Decode the url string
    if (!urlStr || urlStr.length < 1) {
        [self updateSeafToolbar:0];
        return NO;
    }
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
    [self updateSeafToolbar:flag];
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
    NSMutableArray *litems = [[NSMutableArray alloc] init];
    UIBarButtonItem *cancelItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)];
    UIBarButtonItem *saveItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave target:self action:@selector(save)];
    ep = nil;
    [litems addObject:cancelItem];
    [litems addObject:saveItem];

    if ([self IsMarkdown]) {
        ep = [self getTextBarItem:@"Preview" action:@selector(edit_preview) active:0];
        [litems addObject:ep];
        path = [[NSBundle mainBundle] pathForResource:@"edit_file_md" ofType:@"html"];
    } else if ([self IsSeaf]) {
        if (IsIpad()) {
            path = [[NSBundle mainBundle] pathForResource:@"edit_file_seaf2" ofType:@"html"];
            timer = [NSTimer scheduledTimerWithTimeInterval:0.1 target:self selector:@selector(checkBtState:) userInfo:nil repeats:YES];
        } else {
            path = [[NSBundle mainBundle] pathForResource:@"edit_file_seaf" ofType:@"html"];
            timer = [NSTimer scheduledTimerWithTimeInterval:0.1 target:self selector:@selector(checkSelection:) userInfo:nil repeats:YES];
        }
    } else
        path = [[NSBundle mainBundle] pathForResource:@"edit_file_text" ofType:@"html"];

    self.navigationItem.leftBarButtonItems = litems;

    NSURL *url = [NSURL fileURLWithPath:path];
    NSURLRequest *request = [[NSURLRequest alloc] initWithURL:url cachePolicy: NSURLRequestUseProtocolCachePolicy timeoutInterval: 1];
    [(UIWebView *)self.view loadRequest: request];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    if (!IsIpad()) {
        return (interfaceOrientation == UIInterfaceOrientationPortrait);
    }
    return YES;
}

-(BOOL)shouldAutorotate
{
    return YES;
}

-(NSInteger)supportedInterfaceOrientations
{
    NSInteger mask = 0;
    if ([self shouldAutorotateToInterfaceOrientation: UIInterfaceOrientationLandscapeRight])
        mask |= UIInterfaceOrientationMaskLandscapeRight;
    if ([self shouldAutorotateToInterfaceOrientation: UIInterfaceOrientationLandscapeLeft])
        mask |= UIInterfaceOrientationMaskLandscapeLeft;
    if ([self shouldAutorotateToInterfaceOrientation: UIInterfaceOrientationPortrait])
        mask |= UIInterfaceOrientationMaskPortrait;
    if ([self shouldAutorotateToInterfaceOrientation: UIInterfaceOrientationPortraitUpsideDown])
        mask |= UIInterfaceOrientationMaskPortraitUpsideDown;
    return mask;
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation
{
    [self.webView stringByEvaluatingJavaScriptFromString:[NSString stringWithFormat:@"document.execCommand(resizeTO(%f,%f))", self.webView.frame.size.width, self.webView.frame.size.height]];
}

@end
