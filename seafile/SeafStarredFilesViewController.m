//
//  SeafStarredFilesViewController.m
//  seafile
//
//  Created by Wang Wei on 11/4/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import "SeafAppDelegate.h"
#import "SeafStarredFilesViewController.h"
#import "SeafDetailViewController.h"
#import "SeafStarredFile.h"
#import "FileSizeFormatter.h"
#import "SeafDateFormatter.h"
#import "SeafCell.h"

#import "SeafData.h"
#import "Utils.h"
#import "Debug.h"

@interface SeafStarredFilesViewController ()
@property NSMutableArray *starredFiles;
@property SeafDetailViewController *detailViewController;
@end

@implementation SeafStarredFilesViewController
@synthesize connection = _connection;
@synthesize starredFiles = _starredFiles;
@synthesize detailViewController = _detailViewController;

- (id)initWithStyle:(UITableViewStyle)style
{
    self = [super initWithStyle:style];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    _detailViewController = appdelegate.detailVC;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self getStarredFiles];
    [_detailViewController setPreViewItem:nil];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}

- (void)initTabBarItem
{
    self.title = @"Starred";
    self.tabBarItem.image = [[UIImage alloc] initWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"tab-star" ofType:@"png"]];
}

- (BOOL)handleData:(id)JSON
{
    NSMutableArray *stars = [NSMutableArray array];
    for (NSDictionary *info in JSON) {
        SeafStarredFile *sfile = [[SeafStarredFile alloc] initWithConnection:_connection repo:[info objectForKey:@"repo"] path:[info objectForKey:@"path"] mtime:[[info objectForKey:@"mtime"] integerValue:0] size:[[info objectForKey:@"size"] integerValue:0] org:[[info objectForKey:@"org"] integerValue:0]];
        sfile.delegate = self;
        sfile.starDelegate = self;
        [stars addObject:sfile];
    }
    _starredFiles = stars;
    return YES;
}

- (BOOL)loadCache
{
    id JSON = [_connection getCachedStarredFiles];
    if (!JSON)
        return NO;

    [self handleData:JSON];
    return YES;
}

- (void)getStarredFiles
{
    [_connection getStarredFiles:^(NSHTTPURLResponse *response, id JSON, NSData *data) {
        @synchronized(self) {
            Debug("Success to get starred files ...\n");
            [self handleData:JSON];
            [self.tableView reloadData];
        }
    }
                         failure:^(NSHTTPURLResponse *response, NSError *error, id JSON) {
                             Warning("Failed to get starred files ...\n");
                         }];
}

- (void)setConnection:(SeafConnection *)connection
{
    @synchronized(self) {
        _connection = connection;
        _starredFiles = nil;
        [self loadCache];
        [self.tableView reloadData];
    }
}

- (SeafConnection *)connection
{
    return _connection;
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return _starredFiles.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *CellIdentifier = @"SeafCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        NSArray *cells = [[NSBundle mainBundle] loadNibNamed:@"SeafCell" owner:self options:nil];
        cell = [cells objectAtIndex:0];
    }
    SeafStarredFile *sfile = [_starredFiles objectAtIndex:indexPath.row];
    cell.textLabel.text = sfile.name;
    NSString *sizeStr = [FileSizeFormatter stringFromNumber:[NSNumber numberWithInt:sfile.filesize ] useBaseTen:NO];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@, %@", sizeStr, [SeafDateFormatter stringFromInt:sfile.mtime ]];
    cell.imageView.image = sfile.image;
    return cell;
}


#pragma mark - Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    SeafStarredFile *sfile = [_starredFiles objectAtIndex:indexPath.row];
    sfile.delegate = self;
    [sfile loadContent:NO];
    if (!IsIpad())
        [self.navigationController pushViewController:_detailViewController animated:YES];
    [_detailViewController setPreViewItem:sfile];
}

#pragma mark - SeafDentryDelegate
- (void)entry:(SeafBase *)entry contentUpdated:(BOOL)updated completeness:(int)percent
{
    //Debug("update=%d, percent=%d \n", updated, percent);
    [_detailViewController fileContentLoaded:(SeafFile *)entry result:updated completeness:percent];
}

- (void)entryContentLoadingFailed:(int)errCode entry:(SeafBase *)entry;
{
    [_detailViewController fileContentLoaded:(SeafFile *)entry result:NO completeness:0];
}

- (void)repoPasswordSet:(SeafBase *)entry WithResult:(BOOL)success;
{
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return YES;
}

#pragma mark - SeafStarFileDelegate
- (void)fileStateChanged:(BOOL)starred file:(SeafStarredFile *)sfile
{
    if (starred) {
        if ([_starredFiles indexOfObject:sfile] == NSNotFound)
            [_starredFiles addObject:sfile];
    } else {
        [_starredFiles removeObject:sfile];
    }

    [self.tableView reloadData];
}
@end
