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

- (BOOL) richText
{
    return [sfile.mime isEqualToString:@"text/x-seafile"];
}

- (UIWebView *)webView
{
    return (UIWebView *)self.view;
}
- (void)bold
{
    [self.webView stringByEvaluatingJavaScriptFromString:@"document.execCommand(\"Bold\")"];
}

- (void)italic
{
    [self.webView stringByEvaluatingJavaScriptFromString:@"document.execCommand(\"Italic\")"];
}

- (void)underline
{
    [self.webView stringByEvaluatingJavaScriptFromString:@"document.execCommand(\"Underline\")"];
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
    if (![self richText]) {
        self.navigationItem.rightBarButtonItems = nil;
        return;
    }
    BOOL boldEnabled = [[self.webView stringByEvaluatingJavaScriptFromString:@"document.queryCommandState('Bold')"] boolValue];
    BOOL italicEnabled = [[self.webView stringByEvaluatingJavaScriptFromString:@"document.queryCommandState('Italic')"] boolValue];
    BOOL underlineEnabled = [[self.webView stringByEvaluatingJavaScriptFromString:@"document.queryCommandState('Underline')"] boolValue];
    
    NSMutableArray *items = [[NSMutableArray alloc] init];
    
    UIBarButtonItem *bold = [[UIBarButtonItem alloc] initWithTitle:(boldEnabled) ? @"[B]" : @"B" style:UIBarButtonItemStyleBordered target:self action:@selector(bold)];
    UIBarButtonItem *italic = [[UIBarButtonItem alloc] initWithTitle:(italicEnabled) ? @"[I]" : @"I" style:UIBarButtonItemStyleBordered target:self action:@selector(italic)];
    UIBarButtonItem *underline = [[UIBarButtonItem alloc] initWithTitle:(underlineEnabled) ? @"[U]" : @"U" style:UIBarButtonItemStyleBordered target:self action:@selector(underline)];
    
    [items addObject:underline];
    [items addObject:italic];
    [items addObject:bold];
    
    if (currentBoldStatus != boldEnabled || currentItalicStatus != italicEnabled || currentUnderlineStatus != underlineEnabled || sender == self) {
        self.navigationItem.rightBarButtonItems = items;
        currentBoldStatus = boldEnabled;
        currentItalicStatus = italicEnabled;
        currentUnderlineStatus = underlineEnabled;
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
    timer = [NSTimer scheduledTimerWithTimeInterval:0.1 target:self selector:@selector(checkSelection:) userInfo:nil repeats:YES];
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
    NSString *path = [[NSBundle mainBundle] pathForResource: [self richText]? @"edit_file_seaf":@"edit_file_text" ofType:@"html"];
    NSURL *url = [NSURL fileURLWithPath:path];
    NSURLRequest *request = [[NSURLRequest alloc] initWithURL:url.previewItemURL cachePolicy: NSURLRequestUseProtocolCachePolicy timeoutInterval: 1];
    [(UIWebView *)self.view loadRequest: request];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    if (!IsIpad()) {
        return (interfaceOrientation == UIInterfaceOrientationPortrait);
    }
    return YES;
}

@end
