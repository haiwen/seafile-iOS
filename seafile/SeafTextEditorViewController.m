//
//  SeafTextEditorViewController.m
//  seafile
//
//  Created by Wang Wei on 4/9/13.
//  Copyright (c) 2013 tsinghua. All rights reserved.
//

#import "SeafTextEditorViewController.h"
#import "SeafAppDelegate.h"
#import "ExtentedString.h"
#import "Utils.h"
#import "Debug.h"

@interface SeafTextEditorViewController ()
@property (nonatomic, retain) NSTimer *timer;
@property BOOL currentBoldStatus;
@property BOOL currentItalicStatus;
@property BOOL currentUnderlineStatus;

@property id<QLPreviewItem, PreViewDelegate> sfile;
@end

@implementation SeafTextEditorViewController
@synthesize timer;
@synthesize currentBoldStatus;
@synthesize currentItalicStatus;
@synthesize currentUnderlineStatus;
@synthesize sfile;

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
}
- (void)bold
{
    [self btClicked:@"bold"];
}
- (void)italic
{
    [self btClicked:@"italic"];
}
- (void)underline
{
    [self btClicked:@""];
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
- (void)pic
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

- (void)checkSelection:(id)sender
{
    if ([self IsSeaf]) {
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
    [self checkSelection:self];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
    NSMutableArray *items = [[NSMutableArray alloc] init];
    UIBarButtonItem *cancelItem = [[UIBarButtonItem alloc] initWithTitle:@"Cancel" style:UIBarButtonItemStyleBordered target:self action:@selector(cancel)];
    UIBarButtonItem *saveItem = [[UIBarButtonItem alloc] initWithTitle:@"Save" style:UIBarButtonItemStyleBordered target:self action:@selector(save)];
    [items addObject:cancelItem];
    [items addObject:saveItem];
    self.navigationItem.leftBarButtonItems = items;
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

- (void)setFile:(id<QLPreviewItem, PreViewDelegate>) file
{
    self.sfile = file;
    NSString *path;
    if ([self IsMarkdown])
        path = [[NSBundle mainBundle] pathForResource:@"edit_file_md" ofType:@"html"];
    else if ([self IsSeaf]) {
        path = [[NSBundle mainBundle] pathForResource:@"edit_file_seaf" ofType:@"html"];
        timer = [NSTimer scheduledTimerWithTimeInterval:0.1 target:self selector:@selector(checkSelection:) userInfo:nil repeats:YES];
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
