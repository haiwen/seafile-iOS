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


@interface FileViewController ()<QLPreviewControllerDelegate, QLPreviewControllerDataSource>
@property NSArray *items;
@end


@implementation FileViewController

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
    return IsIpad() || (interfaceOrientation == UIInterfaceOrientationPortrait);
}

#pragma mark -
- (id)init
{
    if (self = [super init]) {
        self.dataSource = self;
        self.delegate = self;
        self.view.autoresizesSubviews = YES;
        self.view.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin| UIViewAutoresizingFlexibleRightMargin| UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleTopMargin;
        self.items = [[NSMutableArray alloc] init];
        [self addObserver:self forKeyPath:@"currentPreviewItemIndex" options:NSKeyValueObservingOptionNew context:nil];
    }
    return self;
}

- (void)setPreItem:(id<QLPreviewItem, PreViewDelegate>)prevItem
{
    if (prevItem)
        self.items = [NSArray arrayWithObject:prevItem];
    else
        self.items = [NSArray arrayWithObject:[PrevFile defaultFile]];
    //Debug("Preview file:%@, %@ [%d]\n", prevItem.previewItemTitle, prevItem.previewItemURL, [QLPreviewController canPreviewItem:prevItem]);

    [self reloadData];
    [self setCurrentPreviewItemIndex:0];
}

- (void)setPreItems:(NSArray *)prevItems current:(id<QLPreviewItem, PreViewDelegate>)item;
{
    self.items = prevItems;
    [self reloadData];
    [self setCurrentPreviewItemIndex:[self.items indexOfObject:item]];
}

- (NSInteger)numberOfPreviewItemsInPreviewController:(QLPreviewController *)controller
{
    return self.items.count;
}

- (id <QLPreviewItem>)previewController:(QLPreviewController *)controller previewItemAtIndex:(NSInteger)index;
{
    if (index < 0 || index >= self.items.count)
        return [PrevFile defaultFile];
    //if (index != self.currentPreviewItemIndex)
    //    [self.selectDelegate willSelect:self.items[index]];
    Debug("item=%@, %@", self.items[index], [self.items[index] previewItemTitle]);
    return self.items[index];
}

- (void)setCurrentPreviewItemIndex:(NSInteger)index
{
    super.currentPreviewItemIndex = index;
    [self.selectDelegate selectItem:(id<QLPreviewItem, PreViewDelegate>)self.items[index]];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context
{
    if ([keyPath isEqualToString:@"currentPreviewItemIndex"]){
        // process here
        [self.selectDelegate selectItem:(id<QLPreviewItem, PreViewDelegate>)self.items[self.currentPreviewItemIndex]];
    }
}

@end
