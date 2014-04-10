//
//  SeafUploadDirVontrollerViewController.m
//  seafile
//
//  Created by Wang Wei on 10/20/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import "SeafDirViewController.h"
#import "SeafAppDelegate.h"
#import "SeafDir.h"
#import "SeafRepos.h"
#import "SeafCell.h"
#import "Debug.h"
#import "UIViewController+Extend.h"
#import "SVProgressHUD.h"

#define TITLE_PASSWORD @"Password of this library"

@interface SeafDirViewController ()<SeafDentryDelegate, UIAlertViewDelegate, EGORefreshTableHeaderDelegate, UIScrollViewDelegate>
@property (strong) SeafDir *curDir;
@property (strong) UIBarButtonItem *chooseItem;
@property (strong, readonly) SeafDir *directory;
@property (strong) id<SeafDirDelegate> delegate;

@property (readonly) EGORefreshTableHeaderView* refreshHeaderView;

@end

@implementation SeafDirViewController
@synthesize directory = _directory;
@synthesize curDir = _curDir;
@synthesize refreshHeaderView = _refreshHeaderView;



- (id)initWithSeafDir:(SeafDir *)dir delegate:(id<SeafDirDelegate>)delegate
{
    if (self = [super init]) {
        self.delegate = delegate;
        _directory = dir;
        _directory.delegate = self;
        [_directory loadContent:NO];
        self.tableView.delegate = self;
    }
    return self;
}

- (void)cancel:(id)sender
{
    [self.delegate cancelChoose:self];
}

- (IBAction)chooseFolder:(id)sender
{
    [self.delegate chooseDir:self dir:_directory];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    if([self respondsToSelector:@selector(edgesForExtendedLayout)])
        self.edgesForExtendedLayout = UIRectEdgeNone;
    if ([self.directory isKindOfClass:[SeafRepos class]]) {
        [self.navigationItem setHidesBackButton:YES];
    } else
        [self.navigationItem setHidesBackButton:NO];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Cancel", @"Seafile") style:UIBarButtonItemStyleBordered target:self action:@selector(cancel:)];
    self.tableView.scrollEnabled = YES;
    UIBarButtonItem *flexibleFpaceItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    self.chooseItem = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Choose", @"Seafile") style:UIBarButtonItemStyleBordered target:self action:@selector(chooseFolder:)];
    NSArray *items = [NSArray arrayWithObjects:flexibleFpaceItem, self.chooseItem, flexibleFpaceItem, nil];
    [self setToolbarItems:items];
    self.title = _directory.name;

    if (_refreshHeaderView == nil) {
        EGORefreshTableHeaderView *view = [[EGORefreshTableHeaderView alloc] initWithFrame:CGRectMake(0.0f, 0.0f - self.tableView.bounds.size.height, self.view.frame.size.width, self.tableView.bounds.size.height)];
        view.delegate = self;
        [self.tableView addSubview:view];
        _refreshHeaderView = view;
    }
    [_refreshHeaderView refreshLastUpdatedDate];
}

- (void)viewDidAppear:(BOOL)animated
{
    [self.navigationController setToolbarHidden:NO];
    if ([_directory isKindOfClass:[SeafRepos class]]) {
        [self.chooseItem setEnabled:NO];
    }
}
- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return NSLocalizedString(@"Choose", @"Seafile");
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    int i;
    for (i = 0; i < _directory.items.count; ++i) {
        if (![[_directory.items objectAtIndex:i] isKindOfClass:[SeafDir class]]) {
            break;
        }
    }
    return i;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *CellIdentifier = @"SeafDirCell";
    SeafCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        NSArray *cells = [[NSBundle mainBundle] loadNibNamed:CellIdentifier owner:self options:nil];
        cell = [cells objectAtIndex:0];
    }

    SeafDir *sdir = [_directory.items objectAtIndex:indexPath.row];
    cell.textLabel.text = sdir.name;
    cell.textLabel.font = [UIFont systemFontOfSize:17];
    cell.imageView.image = sdir.image;
    cell.detailTextLabel.text = nil;
    return cell;
}

// Override to support conditional editing of the table view.
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    return NO;
}


#pragma mark - Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    _curDir = [_directory.items objectAtIndex:indexPath.row];
    if ([_curDir isKindOfClass:[SeafRepo class]] && [(SeafRepo *)_curDir passwordRequired]) {
        [self popupSetRepoPassword];
        return;
    }
    SeafDirViewController *controller = [[SeafDirViewController alloc] initWithSeafDir:_curDir delegate:self.delegate];
    [self.navigationController pushViewController:controller animated:YES];
}


#pragma mark - UIAlertViewDelegate
- (void)alertView:(UIAlertView *)alertView willDismissWithButtonIndex:(NSInteger)buttonIndex
{
    if (buttonIndex != alertView.cancelButtonIndex) {
        UITextField *textfiled = [alertView textFieldAtIndex:0];
        NSString *input = textfiled.text;
        if (!input) {
             [self alertWithMessage:NSLocalizedString(@"Password must not be empty", @"Seafile")];
            return;
        }
        if (input.length < 3 || input.length  > 100) {
             [self alertWithMessage:NSLocalizedString(@"The length of password should be between 3 and 100", @"Seafile")];
            return;
        }
        [_curDir setDelegate:self];
        if ([_directory->connection localDecrypt:_curDir.repoId])
            [_curDir checkRepoPassword:input];
        else
            [_curDir setRepoPassword:input];
        [SVProgressHUD showWithStatus:NSLocalizedString(@"Checking library password ...", @"Seafile")];
        return;
    } else if ([alertView.title isEqualToString:TITLE_PASSWORD]) {
        [self popupSetRepoPassword];
    }
}

- (void)popupSetRepoPassword
{
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Password of this library", @"Seafile") message:nil delegate:self cancelButtonTitle:NSLocalizedString(@"Cancel", @"Seafile") otherButtonTitles:NSLocalizedString(@"OK", @"Seafile"), nil];
    alert.alertViewStyle = UIAlertViewStyleSecureTextInput;
    [alert show];
}

#pragma mark - SeafDentryDelegate
- (void)entryChanged:(SeafBase *)entry
{
}

- (void)entry:(SeafBase *)entry contentUpdated:(BOOL)updated completeness:(int)percent
{
    [self doneLoadingTableViewData];
    if (updated) {
        [self.tableView reloadData];
    }
}
- (void)entryContentLoadingFailed:(long)errCode entry:(SeafBase *)entry
{
    [self doneLoadingTableViewData];
    if ([_directory hasCache]) {
        return;
    }
    if (errCode == HTTP_ERR_REPO_PASSWORD_REQUIRED) {
        NSAssert(0, @"Here should never be reached");
    } else {
        [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to load content of the directory", @"Seafile")];
        [self.tableView reloadData];
        Warning("Failed to load directory content %@\n", _directory.name);
    }
}

- (void)repoPasswordSet:(SeafBase *)entry WithResult:(BOOL)success
{
    [SVProgressHUD dismiss];
    if (success) {
        SeafDirViewController *controller = [[SeafDirViewController alloc] initWithSeafDir:_curDir delegate:self.delegate];
        [self.navigationController pushViewController:controller animated:YES];
    } else {
        [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Wrong library password", @"Seafile") duration:2.0];
        [self performSelector:@selector(popupSetRepoPassword) withObject:nil afterDelay:1.0];
    }
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return YES;
}

- (void)viewDidUnload
{
    [super viewDidUnload];
}

- (void)doneLoadingTableViewData
{
    [_refreshHeaderView egoRefreshScrollViewDataSourceDidFinishedLoading:self.tableView];
}

#pragma mark - mark UIScrollViewDelegate Methods
- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    [_refreshHeaderView egoRefreshScrollViewDidScroll:scrollView];
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate
{
    [_refreshHeaderView egoRefreshScrollViewDidEndDragging:scrollView];
}

#pragma mark - EGORefreshTableHeaderDelegate Methods
- (void)egoRefreshTableHeaderDidTriggerRefresh:(EGORefreshTableHeaderView*)view
{
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    if (![appdelegate checkNetworkStatus]) {
        [self performSelector:@selector(doneLoadingTableViewData) withObject:nil afterDelay:0.1];
        return;
    }

    _directory.delegate = self;
    [_directory loadContent:YES];
}

- (BOOL)egoRefreshTableHeaderDataSourceIsLoading:(EGORefreshTableHeaderView*)view
{
    return NO;
}

- (NSDate*)egoRefreshTableHeaderDataSourceLastUpdated:(EGORefreshTableHeaderView*)view
{
    return [NSDate date];
}

@end
