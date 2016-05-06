//
//  SeafTextEditorViewController.m
//  seafile
//
//  Created by Wang Wei on 4/9/13.
//  Copyright (c) 2013 Seafile Ltd.  All rights reserved.
//

#import "SeafTextEditorViewController.h"
#import "SeafAppDelegate.h"

#import "UIViewController+Extend.h"
#import "ExtentedString.h"
#import "Utils.h"
#import "Debug.h"



@interface SeafTextEditorViewController ()
@property UIBarButtonItem *saveItem;

@property id<SeafPreView> previewFile;

@end

@implementation SeafTextEditorViewController


- (id)initWithFile:(id<SeafPreView>)file
{
    self = [self initWithAutoPlatformNibName];
    self.previewFile = file;
    return self;
}

- (UITextView *)textView
{
    return (UITextView *)self.view;
}



- (UIBarButtonItem *)getTextBarItem:(NSString *)title action:(SEL)action active:(int)active
{
    UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithTitle:title style:UIBarButtonItemStylePlain target:self action:action];
    return item;
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
    NSString *content = [[self textView] text];
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
    self.navigationItem.rightBarButtonItems = nil;
    self.navigationController.navigationBar.tintColor = BAR_COLOR;

    UIBarButtonItem *cancelItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)];
    self.navigationItem.rightBarButtonItem = cancelItem;

    self.saveItem = [self getTextBarItem:NSLocalizedString(@"Save", @"Seafile") action:@selector(save) active:0];
    NSMutableArray *litems = [[NSMutableArray alloc] initWithObjects:self.saveItem, nil];
    self.navigationItem.leftBarButtonItems = litems;

    [[self textView] setText:_previewFile.strContent];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}

- (void)viewDidAppear:(BOOL)animated
{
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShown:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)keyboardWillShown:(NSNotification*)aNotification
{
    NSDictionary *info = [aNotification userInfo];
    CGSize kbSize = [info[UIKeyboardFrameBeginUserInfoKey] CGRectValue].size;
    UIEdgeInsets contentInsets = UIEdgeInsetsMake(0.0, 0.0, kbSize.height, 0.0);

    self.textView.contentInset = contentInsets;
    self.textView.scrollIndicatorInsets = contentInsets;
}

- (void)keyboardWillHide:(NSNotification*)aNotification
{
    self.textView.contentInset = UIEdgeInsetsZero;
    self.textView.scrollIndicatorInsets = UIEdgeInsetsZero;
}

-(BOOL)shouldAutorotate
{
    return YES;
}

-(UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskAll;
}
@end
