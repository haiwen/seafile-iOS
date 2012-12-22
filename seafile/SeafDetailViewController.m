//
//  SeafDetailViewController.m
//  seafile
//
//  Created by Wei Wang on 7/7/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import "SeafAppDelegate.h"
#import "SeafDetailViewController.h"
#import "FileViewController.h"

#import "SeafBase.h"
#import "SeafFile.h"

#import "UIViewController+AlertMessage.h"
#import "SVProgressHUD.h"
#import "Debug.h"


@interface SeafDetailViewController ()
@property (strong, nonatomic) UIPopoverController *masterPopoverController;
@property (retain, readonly) FileViewController *fileViewController;
@end


@implementation SeafDetailViewController
@synthesize preViewItem = _preViewItem;
@synthesize masterPopoverController = _masterPopoverController;
@synthesize fileViewController = _fileViewController;


#pragma mark - Managing the detail item
- (FileViewController *)fileViewController
{
    if (_fileViewController)
        return _fileViewController;
    _fileViewController = [[FileViewController alloc] initWithNavigationItem:self.navigationItem ];
    return _fileViewController;
}

- (void)setPreViewItem:(SeafFile *)item
{
    if (self.masterPopoverController != nil) {
        [self.masterPopoverController dismissPopoverAnimated:YES];
    }
    if (_preViewItem == item)
        return;

    _preViewItem = item;
#if 1
    if (_preViewItem) {
        if (!self.fileViewController.view.superview)
            [self.view addSubview:self.fileViewController.view];
        [self.fileViewController setPreItem:_preViewItem];
    } else if (self.fileViewController.view.superview) {
        [self.fileViewController.view removeFromSuperview];
    }
#else
    if (_preViewItem) {
        if ([self.navigationController topViewController] != _fileViewController) {
            [self.navigationController pushViewController:_fileViewController animated:NO];
        }
        [_fileViewController setPreItem:_preViewItem];
    } else if ([self.navigationController topViewController] == _fileViewController) {
        [self.navigationController popToRootViewControllerAnimated:NO];
    }
#endif
}

- (void)goBack:(id)sender
{
    [self.navigationController popViewControllerAnimated:YES];
    [self setPreViewItem:nil];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    if (!IsIpad()) {
        UIBarButtonItem *barButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"All files" style:UIBarButtonItemStyleDone target:self action:@selector(goBack:)];
        [self.navigationItem setLeftBarButtonItem:barButtonItem animated:YES];
    }
}

- (void)viewDidUnload
{
    [super viewDidUnload];
    // Release any retained subviews of the main view.
    _preViewItem = nil;
    _fileViewController = nil;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return YES;
}

#pragma mark - Split view

- (void)splitViewController:(UISplitViewController *)splitController willHideViewController:(UIViewController *)viewController withBarButtonItem:(UIBarButtonItem *)barButtonItem forPopoverController:(UIPopoverController *)popoverController
{
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];

    barButtonItem.title = appdelegate.masterVC.title;
    [self.navigationItem setLeftBarButtonItem:barButtonItem animated:YES];
    self.masterPopoverController = popoverController;
}

- (void)splitViewController:(UISplitViewController *)splitController willShowViewController:(UIViewController *)viewController invalidatingBarButtonItem:(UIBarButtonItem *)barButtonItem
{
    // Called when the view is shown again in the split view, invalidating the button and popover controller.
    [self.navigationItem setLeftBarButtonItem:nil animated:YES];
    self.masterPopoverController = nil;
}

- (void)fileContentLoaded :(SeafFile *)file result:(BOOL)res completeness:(int)percent
{
    if (file != _preViewItem)
        return;
    [_fileViewController updateDownloadProgress:res completeness:percent];
}

@end
