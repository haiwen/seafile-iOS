//
//  SeafUploadDirVontrollerViewController.m
//  seafile
//
//  Created by Wang Wei on 10/20/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import "SeafUploadDirViewController.h"
#import "SeafAppDelegate.h"
#import "InputAlertPrompt.h"
#import "SeafDir.h"
#import "SeafRepos.h"
#import "SeafCell.h"
#import "Debug.h"
#import "UIViewController+AlertMessage.h"
#import "SVProgressHUD.h"


@interface SeafUploadDirViewController ()
@property (strong) InputAlertPrompt *passSetView;
@property (strong) SeafDir *curDir;
@end

@implementation SeafUploadDirViewController
@synthesize passSetView = _passSetView;
@synthesize directory = _directory;
@synthesize curDir = _curDir;

- (id)initWithStyle:(UITableViewStyle)style
{
    self = [super initWithStyle:style];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (id)initWithSeafDir:(SeafDir *)dir
{
    if (self = [self init]) {
        _directory = dir;
        self.title = _directory.name;
        _directory.delegate = self;
        [_directory loadContent:NO];
    }
    return self;
}

- (void)cancel:(id)sender
{
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

- (void)chooseFolder:(id)sender
{
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
    [appdelegate.uploadVC chooseUploadDir:_directory];
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    // Uncomment the following line to preserve selection between presentations.
    // self.clearsSelectionOnViewWillAppear = NO;
    UIBarButtonItem *backItem = [[UIBarButtonItem alloc] initWithTitle:_directory.name style:UIBarButtonItemStyleBordered target:self action:nil];
    self.navigationItem.backBarButtonItem = backItem;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Cancel" style:UIBarButtonItemStyleBordered target:self action:@selector(cancel:)];
    self.tableView.scrollEnabled = YES;

    [self.navigationController setToolbarHidden:NO];
    UIBarButtonItem *flexibleFpaceItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    UIBarButtonItem *chooseItem = [[UIBarButtonItem alloc] initWithTitle:@"Choose Current Folder"  style:UIBarButtonItemStyleBordered target:self action:@selector(chooseFolder:)];
    NSArray *items = [NSArray arrayWithObjects:flexibleFpaceItem, chooseItem, flexibleFpaceItem, nil];
    [self setToolbarItems:items];

    if ([_directory isKindOfClass:[SeafRepos class]]) {
        [chooseItem setEnabled:NO];
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
    return @"Choose a folder to upload the file";
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
    SeafUploadDirViewController *controller = [[SeafUploadDirViewController alloc] initWithSeafDir:_curDir];
    [self.navigationController pushViewController:controller animated:YES];
}


#pragma mark - InputDoneDelegate
- (BOOL)inputDone:(InputAlertPrompt *)alertView input:(NSString *)input errmsg:(NSString **)errmsg;
{
    if (!input) {
        *errmsg = @"Password must not be empty";
        return NO;
    }
    if (input.length < 3 || input.length  > 100) {
        *errmsg = @"The length of password should be between 3 and 100";
        return NO;
    }
    [_curDir setDelegate:self];
    [_curDir setRepoPassword:input];
    [_passSetView.inputTextField setEnabled:NO];
    return YES;
}

- (void)alertView:(UIAlertView *)alertView willDismissWithButtonIndex:(NSInteger)buttonIndex
{
    _passSetView = nil;
}

- (void)popupSetRepoPassword
{
    _passSetView = [[InputAlertPrompt alloc] initWithTitle:@"Password of this library" delegate:self autoDismiss:NO];
    _passSetView.inputTextField.secureTextEntry = YES;
    _passSetView.inputTextField.placeholder = @"Password";
    _passSetView.inputTextField.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    _passSetView.inputTextField.clearButtonMode = UITextFieldViewModeWhileEditing;
    _passSetView.inputTextField.returnKeyType = UIReturnKeyDone;
    _passSetView.inputTextField.keyboardType = UIKeyboardTypeASCIICapable;
    _passSetView.inputTextField.autocorrectionType = UITextAutocapitalizationTypeNone;
    _passSetView.inputDoneDelegate = self;
    [_passSetView show];
}

#pragma mark - SeafDentryDelegate
- (void)entryChanged:(SeafBase *)entry
{
}

- (void)entry:(SeafBase *)entry contentUpdated:(BOOL)updated completeness:(int)percent
{
    if (updated) {
        [self.tableView reloadData];
    }
}
- (void)entryContentLoadingFailed:(int)errCode entry:(SeafBase *)entry
{
    if ([_directory hasCache]) {
        return;
    }
    if (errCode == HTTP_ERR_REPO_PASSWORD_REQUIRED) {
        NSAssert(0, @"Here should never be reached");
    } else {
        [SVProgressHUD showErrorWithStatus:@"Failed to load content of the directory"];
        [self.tableView reloadData];
        Warning("Failed to load directory content %@\n", _directory.name);
    }
}

- (void)repoPasswordSet:(SeafBase *)entry WithResult:(BOOL)success
{
    if (success) {
        [self.passSetView dismissWithClickedButtonIndex:0 animated:YES];
        SeafUploadDirViewController *controller = [[SeafUploadDirViewController alloc] initWithSeafDir:_curDir];
        [self.navigationController pushViewController:controller animated:YES];
    } else {
        [self alertWithMessage:@"Wrong library password"];
        [_passSetView.inputTextField setEnabled:YES];
    }
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return YES;
}

@end
