//
//  FileViewController.m
//  seafile
//
//  Created by Wang Wei on 10/11/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import "FileViewController.h"
#import "Debug.h"

@interface PrevFile : NSObject<QLPreviewItem>
@end

static PrevFile *pfile;

@implementation PrevFile

- (NSString *)previewItemTitle
{
    return nil;
}

- (NSURL *)previewItemURL
{
    NSString *path = [[NSBundle mainBundle] pathForResource:@"app-icon-ipad-50" ofType:@"png"];
    return [NSURL fileURLWithPath:path];
}

+ (PrevFile *)defaultFile
{
    if (!pfile)
        pfile = [[PrevFile alloc] init];
    return pfile;
}


@end


@interface FileViewController ()
@property id<QLPreviewItem, PreViewDelegate> preViewItem;
@end


@implementation FileViewController
@synthesize preViewItem = _preViewItem;

- (void)didReceiveMemoryWarning
{
    // Releases the view if it doesn't have a superview.
    [super didReceiveMemoryWarning];

    // Release any cached data, images, etc that aren't in use.
}

#pragma mark - View lifecycle

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view from its nib.
}

- (void)viewDidUnload
{
    [super viewDidUnload];
    // Release any retained subviews of the main view.
    // e.g. self.myOutlet = nil;
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    if (!IsIpad()) {
        return (interfaceOrientation == UIInterfaceOrientationPortrait);
    }
    return YES;
}

#pragma mark -
- (id)init
{
    if (self = [super init]) {
        self.dataSource = self;
        self.view.autoresizesSubviews = YES;
        //self.view.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
        self.view.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin| UIViewAutoresizingFlexibleRightMargin| UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleTopMargin;
    }
    return self;
}

- (void)setPreItem:(id<QLPreviewItem, PreViewDelegate>)prevItem
{
    _preViewItem = prevItem;
    Debug("Preview file:%@,%@,%@ [%d]\n", _preViewItem.previewItemTitle, [_preViewItem checkoutURL],_preViewItem.previewItemURL, [QLPreviewController canPreviewItem:_preViewItem]);

    [self reloadData];
    [self setCurrentPreviewItemIndex:0];
}

- (NSInteger)numberOfPreviewItemsInPreviewController:(QLPreviewController *)controller
{
    return 1;
}

- (id <QLPreviewItem>)previewController:(QLPreviewController *)controller previewItemAtIndex:(NSInteger)index;
{
    if (_preViewItem)
        return _preViewItem;
    return [PrevFile defaultFile];
}

@end
