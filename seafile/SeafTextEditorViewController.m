//
//  SeafTextEditorViewController.m
//  seafile
//
//  Created by Wang Wei on 4/9/13.
//  Copyright (c) 2013 Seafile Ltd.  All rights reserved.
//

#import "SeafTextEditorViewController.h"
#import "SeafAppDelegate.h"
#import "EGOTextView.h"

#import "UIViewController+Extend.h"
#import "ExtentedString.h"
#import "Utils.h"
#import "Debug.h"

#define TOP_VIEW_HEIGHT 44

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

@interface SeafTextEditorViewController ()<EGOTextViewDelegate>
@property UIBarButtonItem *ep;
@property UIBarButtonItem *saveItem;
@property (strong, nonatomic) IBOutlet UIView *topview;
@property (strong, nonatomic) IBOutlet UIView *seafTopview;

@property id<SeafPreView> previewFile;
@property int flags;

@property float barHeight;

@property(nonatomic,retain) EGOTextView *egoTextView;

@end

@implementation SeafTextEditorViewController


- (id)initWithFile:(id<SeafPreView>)file
{
    self = [self initWithAutoPlatformNibName];
    self.previewFile = file;
    return self;
}

- (BOOL)IsSeaf
{
    return [_previewFile.mime isEqualToString:@"text/x-seafile"];
}

- (BOOL)IsMarkdown
{
    return [_previewFile.mime isEqualToString:@"text/x-markdown"];
}

- (BOOL)IsRawText
{
    return ![self IsSeaf] && ![self IsMarkdown];
}

- (UIWebView *)webView
{
    return (UIWebView *)self.view;
}


- (void)btClicked:(NSString *)tag
{
    [self.webView stringByEvaluatingJavaScriptFromString:[NSString stringWithFormat:@"btClicked(\"%@\")", tag]];
    //[self checkBtState:nil];
}

- (void)edit_preview
{
    if ([self.ep.title isEqualToString:NSLocalizedString(@"Preview", @"Seafile")]) {
        self.ep.title = NSLocalizedString(@"Edit", @"Seafile");
        self.egoTextView.hidden = YES;
        NSString *js = [NSString stringWithFormat:@"setContent(\"%@\");", [self.egoTextView.text stringEscapedForJavasacript]];
        [self.webView stringByEvaluatingJavaScriptFromString:js];
    } else {
        self.ep.title = NSLocalizedString(@"Preview", @"Seafile");
        self.egoTextView.hidden = NO;
        [self.egoTextView becomeFirstResponder];
    }
}

- (IBAction)bold:(id)sender {
    [self btClicked:@"bold"];
}
- (IBAction)italic:(id)sender {
    [self btClicked:@"italic"];
}
- (IBAction)strike:(id)sender {
    [self btClicked:@"strike"];
}
- (IBAction)underline:(id)sender {
    [self btClicked:@"underline"];
}
- (IBAction)ul:(id)sender {
    [self btClicked:@"ulist"];
}
- (IBAction)ol:(id)sender {
    [self btClicked:@"olist"];
}
- (IBAction)indent:(id)sender {
    [self btClicked:@"indent"];
}
- (IBAction)outdent:(id)sender {
    [self btClicked:@"outdent"];
}
- (IBAction)left:(id)sender {
    [self btClicked:@"left"];
}
- (IBAction)center:(id)sender {
    [self btClicked:@"center"];
}
- (IBAction)right:(id)sender {
    [self btClicked:@"right"];
}
- (IBAction)justify:(id)sender {
    [self btClicked:@"justify"];
}
- (IBAction)undo:(id)sender {
    [self btClicked:@"undo"];
}
- (IBAction)redo:(id)sender {
    [self btClicked:@"redo"];
}

- (void)replaceSelectedWith:(NSString *)dft before:(NSString *)before after:(NSString *)after
{
    NSRange r = self.egoTextView.selectedRange;
    NSString *selected = dft;
    if (r.length > 0)
        selected = [[self.egoTextView.attributedString attributedSubstringFromRange:r] string];
    NSString *news = [NSString stringWithFormat:@"%@%@%@", before, selected, after];
    Debug("r=%lu, %lu, %@, %@", (unsigned long)r.location, (unsigned long)r.length, selected, news);
    [self.egoTextView replaceNSRange:r withText:news];
    NSRange selectR = (NSRange) {r.location + before.length, selected.length};
    self.egoTextView.selectedRange = selectR;
}
- (void)insertString:(NSString *)s
{
    NSRange r = self.egoTextView.selectedRange;
    [self.egoTextView replaceNSRange:self.egoTextView.selectedRange withText:s];
    self.egoTextView.selectedRange = (NSRange) {r.location + 1, 0};;
}
- (IBAction)olM:(id)sender {
    [self replaceSelectedWith:@"List item" before:@"\n 1. " after:@""];
}
- (IBAction)ulM:(id)sender {
    [self replaceSelectedWith:@"List item" before:@"\n - " after:@""];
}
- (IBAction)codeM:(id)sender {
    [self replaceSelectedWith:@"enter code here" before:@"`" after:@"`"];
}
- (IBAction)quoteM:(id)sender {
    [self replaceSelectedWith:@"Blockquote" before:@"\n> " after:@""];
}
- (IBAction)insertLinkM:(id)sender {
    [self replaceSelectedWith:@"link" before:@"[" after:@"](http://example.com/)"];
}
- (IBAction)italicM:(id)sender {
    [self replaceSelectedWith:@"emphasized text" before:@"*" after:@"*"];
}
- (IBAction)boldM:(id)sender {
    [self replaceSelectedWith:@"strong text" before:@"**" after:@"**"];
}
- (IBAction)equalM:(id)sender {
    [self insertString:@"="];
}
- (IBAction)asteriskM:(id)sender {
    [self insertString:@"*"];
}
- (IBAction)poundM:(id)sender {
    [self insertString:@"#"];
}

- (UIBarButtonItem *)getTextBarItem:(NSString *)title action:(SEL)action active:(int)active
{
    UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithTitle:title style:UIBarButtonItemStyleBordered target:self action:action];
    return item;
}

- (void)updateSeafToolbar:(int)flag
{
    if (flag == _flags)
        return;
    _flags = flag;
    for (UIView *v in self.seafTopview.subviews) {
        UIButton *btn = (UIButton *)v;
        btn.selected = (flag & (1 << btn.tag)) != 0;
    }
}

- (void)checkBtState:(id)sender
{
    if ([self IsSeaf]) {
        NSString *str = [self.webView stringByEvaluatingJavaScriptFromString:@"getBtState()"];
        [self handleUrl:str];
    }
}

- (void)dismissCurrentView
{
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

- (void)cancel
{
    [self dismissCurrentView];
}

- (void)save
{
    NSString *content = [self IsSeaf] ? [self.webView stringByEvaluatingJavaScriptFromString:@"getContent()"] : self.egoTextView.text;
    [_previewFile saveStrContent:content];
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    [self.detailViewController refreshView];
    [appdelegate.fileVC refreshView];
    [appdelegate.starredVC refreshView];
    [self dismissCurrentView];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    if([self respondsToSelector:@selector(edgesForExtendedLayout)])
        self.edgesForExtendedLayout = UIRectEdgeNone;
    // Do any additional setup after loading the view from its nib.
    self.flags = -1;
    self.navigationItem.rightBarButtonItems = nil;
    self.navigationController.navigationBar.tintColor = BAR_COLOR;

    EGOTextView *view = [[EGOTextView alloc] initWithFrame:self.view.bounds];
    view.correctable = NO;
    view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    view.frame = self.view.frame;
    view.delegate = self;
    [self.view addSubview:view];
    self.egoTextView = view;
    UIBarButtonItem *cancelItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)];
    self.navigationItem.rightBarButtonItem = cancelItem;

    self.saveItem = [self getTextBarItem:NSLocalizedString(@"Save", @"Seafile") action:@selector(save) active:0];
    [self start];
}
- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
    [super viewWillAppear:animated];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillHideNotification object:nil];
}
- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}

# pragma - UIWebViewDelegate
- (void)webViewDidFinishLoad:(UIWebView *)webView
{
    NSString *js = [NSString stringWithFormat:@"setContent(\"%@\");", [_previewFile.strContent stringEscapedForJavasacript]];
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
    } else if ([urlStr.lowercaseString hasPrefix:@"file://"])
        return YES;
    return NO;
}

- (void)start
{
    if (![self IsSeaf]) {
        [self prepareRawText];
    } else {
        [self prepareSeaf];
    }
}

- (void)prepareRawText
{
    self.egoTextView.hidden = NO;
    self.egoTextView.text = _previewFile.strContent;
    NSMutableArray *litems = [[NSMutableArray alloc] init];
    [litems addObject:self.saveItem];
    if ([self IsMarkdown]) {
        self.ep = [self getTextBarItem:NSLocalizedString(@"Preview", @"Seafile") action:@selector(edit_preview) active:0];
        [litems addObject:self.ep];
        NSURLRequest *request = [[NSURLRequest alloc] initWithURL:_previewFile.previewItemURL cachePolicy: NSURLRequestUseProtocolCachePolicy timeoutInterval: 1];
        [self.webView loadRequest:request];
    }
    self.navigationItem.leftBarButtonItems = litems;
    self.egoTextView.selectedRange = (NSRange) {0, 0};
}

- (void)prepareSeaf
{
    self.navigationItem.leftBarButtonItem = self.saveItem;
    self.egoTextView.hidden = YES;;
    NSString *path = [[NSBundle mainBundle] pathForResource:@"edit_file_seaf" ofType:@"html"];
    NSURL *url = [NSURL fileURLWithPath:path];
    NSURLRequest *request = [[NSURLRequest alloc] initWithURL:url cachePolicy: NSURLRequestUseProtocolCachePolicy timeoutInterval: 3];
    [(UIWebView *)self.view loadRequest: request];
}

-(BOOL)shouldAutorotate
{
    return YES;
}

-(UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskAll;
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation
{
    [self.webView stringByEvaluatingJavaScriptFromString:[NSString stringWithFormat:@"document.execCommand(resizeTO(%f,%f))", self.webView.frame.size.width, self.webView.frame.size.height]];
}

#pragma mark EGOTextViewDelegate

- (BOOL)egoTextViewShouldBeginEditing:(EGOTextView *)textView {
    return YES;
}

- (BOOL)egoTextViewShouldEndEditing:(EGOTextView *)textView {
    return YES;
}

- (void)egoTextViewDidBeginEditing:(EGOTextView *)textView {
    [self.egoTextView setSelectedRange:NSMakeRange(0,0)];
}

- (void)egoTextViewDidEndEditing:(EGOTextView *)textView {
}

- (void)egoTextViewDidChange:(EGOTextView *)textView {
}

- (void)egoTextView:(EGOTextView*)textView didSelectURL:(NSURL *)URL {
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
        if ([[possibleFormView description] rangeOfString:@"UIPeripheralHostView"].location != NSNotFound) {
            for (UIView *subviewWhichIsPossibleFormView in [possibleFormView subviews]) {
                // hides the accessory bar
                if ([[subviewWhichIsPossibleFormView description] rangeOfString:@"UIWebFormAccessory"].location != NSNotFound) {
                    self.barHeight = subviewWhichIsPossibleFormView.frame.size.height;
                    [subviewWhichIsPossibleFormView removeFromSuperview];
                }
                // hides the backdrop (iOS 7)
                if ([[subviewWhichIsPossibleFormView description] hasPrefix:@"<UIKBInputBackdropView"]) {
                    if ([subviewWhichIsPossibleFormView frame].origin.y == 0){
                        [[subviewWhichIsPossibleFormView layer] setOpacity:0.0];
                    }
                }
                // hides the thin grey line used to adorn the bar (iOS 6)
                if([[subviewWhichIsPossibleFormView description] rangeOfString:@"UIImageView"].location != NSNotFound){
                     [[subviewWhichIsPossibleFormView layer] setOpacity: 0.0];
                }
            }
        }
    }

    self.seafTopview.frame = CGRectMake(0, self.seafTopview.frame.origin.y + self.barHeight, self.seafTopview.frame.size.width, self.seafTopview.frame.size.height);
    [self.view addSubview:self.seafTopview];
    [self.view bringSubviewToFront:self.seafTopview];
}

- (void)keyboardWillShow:(NSNotification *)notification {
    NSDictionary* info = [notification userInfo];
    CGSize keyBoardSize = [[info objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue].size;
    float keyH = MIN(keyBoardSize.height, keyBoardSize.width);

    if ([self IsRawText]) {
        self.egoTextView.frame = CGRectMake(self.egoTextView.frame.origin.x, self.egoTextView.frame.origin.y, self.egoTextView.frame.size.width, self.view.bounds.size.height - keyH );
        return;
    }

    UIView *view = [self IsSeaf] ? self.view : self.egoTextView;
    UIView *topview = [self IsSeaf] ? self.seafTopview : self.topview;
    float height = self.view.bounds.size.height - keyH - TOP_VIEW_HEIGHT;
    if ([self IsMarkdown])
        view.frame = CGRectMake(view.frame.origin.x, view.frame.origin.y, view.frame.size.width, height);
    topview.frame = CGRectMake(0, height, view.frame.size.width, TOP_VIEW_HEIGHT);

    float unit = self.view.bounds.size.width / topview.subviews.count;
    for (int i = 0; i < topview.subviews.count; ++i) {
        UIView *bt = topview.subviews[i];
        float centerX = unit *i + unit/2;
        bt.frame = CGRectMake(centerX - bt.frame.size.width/2, bt.frame.origin.y, bt.frame.size.width, bt.frame.size.height);
    }

    if ([self IsSeaf]) {
        [self performSelector:@selector(removeBar) withObject:nil afterDelay:0];
        return;
    } else {
        [self.view addSubview:topview];
        [self.view bringSubviewToFront:topview];
    }
}

- (void)keyboardWillHide:(NSNotification *)notification{
    UIView *view = [self IsSeaf] ? self.view : self.egoTextView;
    UIView *topview = [self IsSeaf] ? self.seafTopview : self.topview;
    view.frame = CGRectMake(view.frame.origin.x, view.frame.origin.y, view.frame.size.width, self.view.bounds.size.height);
    [view becomeFirstResponder];
    [topview removeFromSuperview];
}

@end
