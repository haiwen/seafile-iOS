//
//  SeafSettingsViewController.m
//  seafile
//
//  Created by Wang Wei on 10/27/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>

#import "SeafAppDelegate.h"
#import "SeafDetailViewController.h"
#import "SeafSettingsViewController.h"
#import "SeafDirViewController.h"
#import "SeafRepos.h"
#import "SeafAvatar.h"
#import "UIViewController+Extend.h"
#import "FileSizeFormatter.h"
#import "ExtentedString.h"
#import "Debug.h"

enum {
    CELL_INVITATION = 0,
    CELL_WEBSITE,
    CELL_SERVER,
    CELL_VERSION,
};

#define SEAFILE_SITE @"http://www.seafile.com"
#define MSG_RESET_UPLOADED NSLocalizedString(@"Do you want reset the uploaded photos?", @"Seafile")
#define MSG_CLEAR_CACHE NSLocalizedString(@"Are you sure to clear all the cache?", @"Seafile")

@interface SeafSettingsViewController ()<SeafDirDelegate, MFMailComposeViewControllerDelegate>
@property (strong, nonatomic) IBOutlet UITableViewCell *nameCell;
@property (strong, nonatomic) IBOutlet UITableViewCell *usedspaceCell;
@property (strong, nonatomic) IBOutlet UITableViewCell *serverCell;
@property (strong, nonatomic) IBOutlet UITableViewCell *cacheCell;
@property (strong, nonatomic) IBOutlet UITableViewCell *versionCell;
@property (strong, nonatomic) IBOutlet UITableViewCell *autoSyncCell;
@property (strong, nonatomic) IBOutlet UITableViewCell *syncRepoCell;
@property (strong, nonatomic) IBOutlet UITableViewCell *tellFriendCell;
@property (strong, nonatomic) IBOutlet UITableViewCell *websiteCell;

@property (strong, nonatomic) IBOutlet UILabel *wipeCacheLabel;
@property (strong, nonatomic) IBOutlet UILabel *autoCameraUploadLabel;
@property (strong, nonatomic) IBOutlet UILabel *wifiOnlyLabel;

@property (strong, nonatomic) IBOutlet UISwitch *autoSyncSwitch;
@property (strong, nonatomic) IBOutlet UISwitch *wifiOnlySwitch;
@property BOOL autoSync;
@property BOOL wifiOnly;

@property int state;

@end

@implementation SeafSettingsViewController

- (id)initWithStyle:(UITableViewStyle)style
{
    self = [super initWithStyle:style];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)autoSyncSwitchFlip:(id)sender
{
    if (_autoSyncSwitch.on) {
        if([ALAssetsLibrary authorizationStatus] == ALAuthorizationStatusNotDetermined) {
            ALAssetsLibrary *assetLibrary = [[ALAssetsLibrary alloc] init];
            /*
             Enumerating assets or groups of assets in the library will present a consent dialog to the user.
             */
            [assetLibrary enumerateGroupsWithTypes:ALAssetsGroupAll usingBlock:^(ALAssetsGroup *group, BOOL *stop) {
                _autoSync =  _autoSyncSwitch.on;
                _connection.autoSync = _autoSync;
            } failureBlock:^(NSError *error) {
                _autoSyncSwitch.on = false;
            }];
        } else if([ALAssetsLibrary authorizationStatus] == ALAuthorizationStatusRestricted ||
                  [ALAssetsLibrary authorizationStatus] == ALAuthorizationStatusDenied) {
            [self alertWithTitle:NSLocalizedString(@"This app does not have access to your photos and videos.", @"Seafile") message:NSLocalizedString(@"You can enable access in Privacy Settings", @"Seafile")];
            _autoSyncSwitch.on = false;
        } else if([ALAssetsLibrary authorizationStatus] == ALAuthorizationStatusAuthorized) {
            _autoSync = _autoSyncSwitch.on;
            _connection.autoSync = _autoSync;
        }
    }
}

- (void)wifiOnlySwitchFlip:(id)sender
{
    _wifiOnly = _wifiOnlySwitch.on;
    _connection.wifiOnly = _wifiOnly;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    _nameCell.textLabel.text = NSLocalizedString(@"Username", @"Seafile");
    _usedspaceCell.textLabel.text = NSLocalizedString(@"Space Used", @"Seafile");
    _autoCameraUploadLabel.text = NSLocalizedString(@"Auto Camera Upload", @"Seafile");
    _wifiOnlyLabel.text = NSLocalizedString(@"Wifi Only", @"Seafile");
    _syncRepoCell.textLabel.text = NSLocalizedString(@"Upload Destination", @"Seafile");
    _cacheCell.textLabel.text = NSLocalizedString(@"Local Cache", @"Seafile");
    _tellFriendCell.textLabel.text = NSLocalizedString(@"Tell Friends about seafile", @"Seafile");
    _websiteCell.textLabel.text = NSLocalizedString(@"Website", @"Seafile");
    _websiteCell.detailTextLabel.text = @"www.seafile.com";
    _serverCell.textLabel.text = NSLocalizedString(@"Server", @"Seafile");
    _versionCell.textLabel.text = NSLocalizedString(@"Version", @"Seafile");
    _wipeCacheLabel.text = NSLocalizedString(@"Wipe Cache", @"Seafile");
    self.title = NSLocalizedString(@"Settings", @"Seafile");

    self.navigationController.navigationBar.tintColor = BAR_COLOR;
    [_autoSyncSwitch addTarget:self action:@selector(autoSyncSwitchFlip:) forControlEvents:UIControlEventValueChanged];
    [_wifiOnlySwitch addTarget:self action:@selector(wifiOnlySwitchFlip:) forControlEvents:UIControlEventValueChanged];
}

- (void)viewWillAppear:(BOOL)animated
{
    dispatch_async(dispatch_get_main_queue(), ^ {
        [self configureView];
    });
    [super viewWillAppear:animated];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (long long)cacheSize
{
    return [Utils folderSizeAtPath:[SeafGlobal.sharedObject applicationDocumentsDirectory]];
}

- (void)configureView
{
    if (!_connection)
        return;

    NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];
    NSString *version = [infoDictionary objectForKey:@"CFBundleVersion"];
    _versionCell.detailTextLabel.text = version;

    _nameCell.detailTextLabel.text = _connection.username;
    _serverCell.detailTextLabel.text = [_connection.address trimUrl];
    _autoSyncSwitch.on = self.autoSync;
    if (self.autoSync)
        [self autoSyncSwitchFlip:nil];
    NSString *autoSyncRepo = [[_connection getAttribute:@"autoSyncRepo"] stringValue];
    SeafRepo *repo = [_connection getRepo:autoSyncRepo];
    _syncRepoCell.detailTextLabel.text = repo ? repo.name : nil;
    long long cacheSize = [self cacheSize];
    _cacheCell.detailTextLabel.text = [FileSizeFormatter stringFromNumber:[NSNumber numberWithLongLong:cacheSize] useBaseTen:NO];
    Debug("%@, %lld, %lld, total cache=%lld", _connection.username, _connection.usage, _connection.quota, cacheSize);
    if (_connection.quota <= 0) {
        if (_connection.usage < 0)
            _usedspaceCell.detailTextLabel.text = @"Unknown";
        else
            _usedspaceCell.detailTextLabel.text = [FileSizeFormatter stringFromNumber:[NSNumber numberWithLongLong:_connection.usage] useBaseTen:NO];
    } else {
        float usage = 100.0 * _connection.usage/_connection.quota;
        NSString *quotaString = [FileSizeFormatter stringFromNumber:[NSNumber numberWithLongLong:_connection.quota ] useBaseTen:NO];
        if (usage < 0)
            _usedspaceCell.detailTextLabel.text = [NSString stringWithFormat:@"? of %@", quotaString];
        else
            _usedspaceCell.detailTextLabel.text = [NSString stringWithFormat:@"%.2f%% of %@", usage, quotaString];
    }
    [self.tableView reloadData];
}

- (void)setConnection:(SeafConnection *)connection
{
    _connection = connection;
    _autoSync = _connection.isAutoSync;
    _wifiOnly = _connection.isWifiOnly;
    [self.tableView reloadData];
    [_connection getAccountInfo:^(bool result, SeafConnection *conn) {
        if (result && conn == self.connection) {
            dispatch_async(dispatch_get_main_queue(), ^ {
                [self configureView];
            });
        }
    }];
}

- (void)popupRepoSelect
{
    SeafDirViewController *c = [[SeafDirViewController alloc] initWithSeafDir:self.connection.rootFolder delegate:self chooseRepo:true];
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:c];
    [navController setModalPresentationStyle:UIModalPresentationFormSheet];
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    [appdelegate.tabbarController presentViewController:navController animated:YES completion:nil];
}

#pragma mark - Table view delegate
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [self.tableView deselectRowAtIndexPath:[self.tableView indexPathForSelectedRow] animated:NO];
    if (indexPath.section == 0) {
        if (indexPath.row == 1) // Select the quota cell
            [_connection getAccountInfo:^(bool result, SeafConnection *conn) {
                if (result && conn == self.connection) {
                    dispatch_async(dispatch_get_main_queue(), ^ {
                        [self configureView];
                    });
                }
            }];
    } else if (indexPath.section == 1) {
        if (indexPath.row == 2) {
            if (_autoSync) {
                [self popupRepoSelect];
            }
        }
    } else if (indexPath.section == 3) {
        _state = (int)indexPath.row;
        switch ((indexPath.row)) {
            case CELL_INVITATION:
                [self sendMailInApp];
                break;

            case CELL_WEBSITE:
                [[UIApplication sharedApplication] openURL:[NSURL URLWithString:SEAFILE_SITE]];
                break;

            case CELL_SERVER:
                [[UIApplication sharedApplication] openURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/", _connection.address]]];
                break;

            default:
                break;
        }
    } else if (indexPath.section == 4) {
        [self alertWithTitle:MSG_CLEAR_CACHE message:nil yes:^{
            SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
            [(SeafDetailViewController *)[appdelegate detailViewControllerAtIndex:TABBED_SETTINGS] setPreViewItem:nil master:nil];
            [Utils clearAllFiles:[[SeafGlobal.sharedObject applicationDocumentsDirectory] stringByAppendingPathComponent:@"objects"]];
            [Utils clearAllFiles:[[SeafGlobal.sharedObject applicationDocumentsDirectory] stringByAppendingPathComponent:@"blocks"]];
            [Utils clearAllFiles:[[SeafGlobal.sharedObject applicationDocumentsDirectory] stringByAppendingPathComponent:@"edit"]];

            [Utils clearAllFiles:[SeafGlobal.sharedObject applicationTempDirectory]];
            [SeafUploadFile clearCache];
            [SeafAvatar clearCache];

            [[SeafGlobal sharedObject] deleteAllObjects:@"Directory"];
            [[SeafGlobal sharedObject] deleteAllObjects:@"DownloadedFile"];
            [[SeafGlobal sharedObject] deleteAllObjects:@"SeafCacheObj"];

            long long cacheSize = [self cacheSize];
            _cacheCell.detailTextLabel.text = [FileSizeFormatter stringFromNumber:[NSNumber numberWithLongLong:cacheSize] useBaseTen:NO];

        } no:nil];
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    NSString *sectionNames[] = {
        NSLocalizedString(@"Account Info", @"Seafile"),
        NSLocalizedString(@"Camera Upload", @"Seafile"),
        NSLocalizedString(@"Cache", @"Seafile"),
        NSLocalizedString(@"About", @"Seafile"),
        @"",
    };
    if (section < 0 || section > 4)
        return nil;
    return sectionNames[section];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return YES;
}

- (void)viewDidUnload {
    [self setNameCell:nil];
    [self setUsedspaceCell:nil];
    [self setServerCell:nil];
    [self setCacheCell:nil];
    [self setVersionCell:nil];
    [super viewDidUnload];
}


#pragma mark - sena mail inside app
- (void)sendMailInApp
{
    Class mailClass = NSClassFromString(@"MFMailComposeViewController");
    if (!mailClass) {
        [self alertWithTitle:NSLocalizedString(@"This function is not supportted yet", @"Seafile")];
        return;
    }
    if (![mailClass canSendMail]) {
        [self alertWithTitle:NSLocalizedString(@"The mail account has not been set yet", @"Seafile")];
        return;
    }
    [self displayMailPicker];
}

- (void)configureInvitationMail:(MFMailComposeViewController *)mailPicker
{
    [mailPicker setSubject:[NSString stringWithFormat:NSLocalizedString(@"%@ invite you to Seafile", @"Seafile"), NSFullUserName()]];
    NSString *emailBody = [NSString stringWithFormat:NSLocalizedString(@"Hey there!<br/><br/> I've been using Seafile and thought you might like it. It is a free way to bring all you files anywhere and share them easily.<br/><br/>Go to the official website of Seafile:</br></br> <a href=\"%@\">%@</a>\n\n", @"Seafile"), SEAFILE_SITE, SEAFILE_SITE];

    [mailPicker setMessageBody:emailBody isHTML:YES];
}

- (void)displayMailPicker
{
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    MFMailComposeViewController *mailPicker = appdelegate.globalMailComposer;
    mailPicker.mailComposeDelegate = self;
    [self configureInvitationMail:mailPicker];
    [appdelegate.tabbarController presentViewController:mailPicker animated:YES completion:nil];
}

#pragma mark - MFMailComposeViewControllerDelegate
- (void)mailComposeController:(MFMailComposeViewController *)controller didFinishWithResult:(MFMailComposeResult)result error:(NSError *)error
{
    NSString *msg;
    switch (result) {
        case MFMailComposeResultCancelled:
            msg = @"cancalled";
            break;
        case MFMailComposeResultSaved:
            msg = @"saved";
            break;
        case MFMailComposeResultSent:
            msg = @"sent";
            break;
        case MFMailComposeResultFailed:
            msg = @"failed";
            break;
        default:
            msg = @"";
            break;
    }
    Debug("state=%d:send mail %@\n", _state, msg);
    [self dismissViewControllerAnimated:YES completion:^{
        SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
        [appdelegate cycleTheGlobalMailComposer];
    }];
}

#pragma mark - SeafDirDelegate
- (void)chooseDir:(UIViewController *)c dir:(SeafDir *)dir
{
    [c.navigationController dismissViewControllerAnimated:YES completion:nil];
    NSString *old = [_connection getAttribute:@"autoSyncRepo"];
    SeafRepo *repo = (SeafRepo *)dir;
    if ([repo.repoId isEqualToString:old]) {
        [_connection checkAutoSync];
        return;
    }
    _syncRepoCell.detailTextLabel.text = repo.name;
    [self.tableView reloadData];
    [_connection setAttribute:repo.repoId forKey:@"autoSyncRepo"];
    dispatch_async(dispatch_get_main_queue(), ^ {
        [self alertWithTitle:MSG_RESET_UPLOADED message:nil yes:^{
            [_connection resetUploadedPhotos];
            [_connection checkAutoSync];
        } no:^{
            [_connection checkAutoSync];
        }];
    });
}

- (void)cancelChoose:(UIViewController *)c
{
    [c.navigationController dismissViewControllerAnimated:YES completion:nil];
}

@end
