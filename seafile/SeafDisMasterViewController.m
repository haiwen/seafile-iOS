//
//  SeafDisMasterViewController.m
//  Discussion
//
//  Created by Wang Wei on 5/21/13.
//  Copyright (c) 2013 Wang Wei. All rights reserved.
//

#import "SeafDisMasterViewController.h"
#import "SeafDisDetailViewController.h"
#import "SeafAppDelegate.h"
#import "SeafDateFormatter.h"
#import "ExtentedString.h"
#import "Debug.h"


@interface SeafDisMasterViewController ()

@end

@implementation SeafDisMasterViewController
@synthesize connection = _connection;

- (void)awakeFromNib
{
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
        self.clearsSelectionOnViewWillAppear = NO;
        self.contentSizeForViewInPopover = CGSizeMake(320.0, 600.0);
    }
    [super awakeFromNib];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(refresh:)];;
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    self.detailViewController = appdelegate.disdetailVC;
    self.navigationItem.leftBarButtonItem = appdelegate.switchItem;
    self.title = @"Groups";
    self.tableView.rowHeight = 50;
    self.detailViewController.connection = _connection;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)refresh:(id)sender
{
    [_connection getSeafGroups:^(NSHTTPURLResponse *response, id JSON, NSData *data) {
        @synchronized(self) {
            Debug("Success to get groups ...\n");
            [self.tableView reloadData];
        }
    }
                         failure:^(NSHTTPURLResponse *response, NSError *error, id JSON) {
                             Warning("Failed to get groups ...\n");
                         }];
}

- (void)setConnection:(SeafConnection *)conn
{
    @synchronized(self) {
        if (_connection != conn) {
            _connection = conn;
            self.detailViewController.group = nil;
            self.detailViewController.connection = conn;
            [self refresh:nil];
        }
    }
}

- (SeafConnection *)connection
{
    return _connection;
}

- (void)viewWillAppear:(BOOL)animated
{
    [self.tableView reloadData];
    [super viewWillAppear:animated];
}

#pragma mark - Table View

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.connection.seafGroups.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *CellIdentifier = @"SeafCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        NSArray *cells = [[NSBundle mainBundle] loadNibNamed:@"SeafCell" owner:self options:nil];
        cell = [cells objectAtIndex:0];
    }
    NSDictionary *dict = [self.connection.seafGroups objectAtIndex:indexPath.row];
    cell.textLabel.text = [dict objectForKey:@"name"];
    int ctime = [[dict objectForKey:@"ctime"] integerValue:0];
    NSString *creator = [dict objectForKey:@"creator"];
    creator = [creator substringToIndex:[creator indexOf:'@']];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ created at %@", creator, [SeafDateFormatter stringFromInt:ctime]];
    cell.imageView.image = [UIImage imageNamed:@"group.png"];
    return cell;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    // Return NO if you do not want the specified item to be editable.
    return NO;
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath
{
    // The table view should not be re-orderable.
    return NO;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (!IsIpad()) {
        [self.navigationController pushViewController:self.detailViewController animated:YES];
    }
    NSString *gid = [[self.connection.seafGroups objectAtIndex:indexPath.row] objectForKey:@"id"];
    self.detailViewController.group = gid;
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if ([[segue identifier] isEqualToString:@"showDetail"]) {
    }
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    if (!IsIpad()) {
        return (interfaceOrientation == UIInterfaceOrientationPortrait);
    }
    return YES;
}

@end
