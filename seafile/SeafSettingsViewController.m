//
//  SeafSettingsViewController.m
//  seafile
//
//  Created by Wang Wei on 10/27/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

@import LocalAuthentication;
@import QuartzCore;

#import "SVProgressHUD.h"

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

enum {
    CELL_CACHE_SIZE = 0,
    CELL_CACHE_WIPE,
};

enum {
    SECTION_ACCOUNT = 0,
    SECTION_CAMERA,
    SECTION_CACHE,
    SECTION_ENC,
    SECTION_ABOUT,
    SECTION_LOGOUT,
};
enum CAMERA_CELL{
    CELL_AUTO = 0,
    CELL_VIDEOS,
    CELL_WIFIONLY,
    CELL_BACKGROUND,
    CELL_DESTINATION,
};

enum ENC_LIBRARIES{
    CELL_CLEAR_PASSWORD = 0,
};

#define SEAFILE_SITE @"http://www.seafile.com"
#define MSG_RESET_UPLOADED NSLocalizedString(@"Do you want reset the uploaded photos?", @"Seafile")
#define MSG_CLEAR_CACHE NSLocalizedString(@"Are you sure to clear all the cache?", @"Seafile")
#define MSG_LOG_OUT NSLocalizedString(@"Are you sure to log out?", @"Seafile")

@interface SeafSettingsViewController ()<SeafDirDelegate, SeafPhotoSyncWatcherDelegate, MFMailComposeViewControllerDelegate, CLLocationManagerDelegate>
@property (strong, nonatomic) IBOutlet UITableViewCell *nameCell;
@property (strong, nonatomic) IBOutlet UITableViewCell *usedspaceCell;
@property (strong, nonatomic) IBOutlet UITableViewCell *serverCell;
@property (strong, nonatomic) IBOutlet UITableViewCell *cacheCell;
@property (strong, nonatomic) IBOutlet UITableViewCell *versionCell;
@property (strong, nonatomic) IBOutlet UITableViewCell *autoSyncCell;
@property (strong, nonatomic) IBOutlet UITableViewCell *syncRepoCell;
@property (strong, nonatomic) IBOutlet UITableViewCell *tellFriendCell;
@property (strong, nonatomic) IBOutlet UITableViewCell *websiteCell;
@property (strong, nonatomic) IBOutlet UITableViewCell *videoSyncCell;
@property (strong, nonatomic) IBOutlet UITableViewCell *backgroundSyncCell;
@property (strong, nonatomic) IBOutlet UITableViewCell *clearEncRepoPasswordCell;
@property (strong, nonatomic) IBOutlet UITableViewCell *wipeCacheCell;

@property (strong, nonatomic) IBOutlet UILabel *logOutLabel;
@property (strong, nonatomic) IBOutlet UILabel *autoCameraUploadLabel;
@property (strong, nonatomic) IBOutlet UILabel *wifiOnlyLabel;
@property (strong, nonatomic) IBOutlet UILabel *videoSyncLabel;
@property (strong, nonatomic) IBOutlet UILabel *backgroundSyncLable;
@property (strong, nonatomic) IBOutlet UILabel *autoClearPasswdLabel;
@property (strong, nonatomic) IBOutlet UILabel *localDecryLabel;
@property (strong, nonatomic) IBOutlet UILabel *enableTouchIDLabel;

@property (strong, nonatomic) IBOutlet UISwitch *autoSyncSwitch;
@property (strong, nonatomic) IBOutlet UISwitch *wifiOnlySwitch;
@property (strong, nonatomic) IBOutlet UISwitch *videoSyncSwitch;
@property (strong, nonatomic) IBOutlet UISwitch *backgroundSyncSwitch;
@property (strong, nonatomic) IBOutlet UISwitch *autoClearPasswdSwitch;
@property (strong, nonatomic) IBOutlet UISwitch *localDecrySwitch;
@property (strong, nonatomic) IBOutlet UISwitch *enableTouchIDSwitch;

@property (strong, nonatomic) CLLocationManager *locationManager;

@property int state;

@property NSString *version;
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

- (BOOL)autoSync
{
    return _connection.autoSync;
}

- (BOOL)wifiOnly
{
    return _connection.wifiOnly;
}

- (BOOL)videoSync
{
    return _connection.videoSync;
}

- (BOOL)backgroundSync
{
    return _connection.backgroundSync;
}

- (void)setAutoSync:(BOOL)autoSync
{
    if (_connection.autoSync == autoSync)
        return;
    _connection.autoSync = autoSync;
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    [appdelegate checkBackgroundUploadStatus];
}

- (void)setVideoSync:(BOOL)videoSync
{
    _connection.videoSync = videoSync;
}

- (void)setWifiOnly:(BOOL)wifiOnly
{
    _connection.wifiOnly = wifiOnly;
}

- (void)setBackgroundSync:(BOOL)backgroundSync
{
    _connection.backgroundSync = backgroundSync;
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    [appdelegate checkBackgroundUploadStatus];
}

- (void)checkPhotoLibraryAuthorizationStatus
{
    Debug("Current AuthorizationStatus:%ld", (long)[ALAssetsLibrary authorizationStatus]);

    if([ALAssetsLibrary authorizationStatus] == ALAuthorizationStatusNotDetermined) {
        ALAssetsLibrary *assetLibrary = [[ALAssetsLibrary alloc] init];
        /*
         Enumerating assets or groups of assets in the library will present a consent dialog to the user.
         */
        [assetLibrary enumerateGroupsWithTypes:ALAssetsGroupAll usingBlock:^(ALAssetsGroup *group, BOOL *stop) {
            self.autoSync = _autoSyncSwitch.on;
            *stop = true;
        } failureBlock:^(NSError *error) {
            _autoSyncSwitch.on = false;
        }];
    } else if([ALAssetsLibrary authorizationStatus] == ALAuthorizationStatusRestricted ||
              [ALAssetsLibrary authorizationStatus] == ALAuthorizationStatusDenied) {
        [self alertWithTitle:NSLocalizedString(@"This app does not have access to your photos and videos.", @"Seafile") message:NSLocalizedString(@"You can enable access in Privacy Settings", @"Seafile")];
        _autoSyncSwitch.on = false;
    } else if([ALAssetsLibrary authorizationStatus] == ALAuthorizationStatusAuthorized) {
        self.autoSync = _autoSyncSwitch.on;
    }
}

- (void)autoSyncSwitchFlip:(id)sender
{
    if (_autoSyncSwitch.on) {
        [self checkPhotoLibraryAuthorizationStatus];
    } else {
        self.autoSync = _autoSyncSwitch.on;
        _syncRepoCell.detailTextLabel.text = @"";
        _connection.autoSyncRepo = nil;
        [self.tableView reloadData];
        [_connection performSelectorInBackground:@selector(checkAutoSync) withObject:nil];
    }
}

- (void)wifiOnlySwitchFlip:(id)sender
{
    self.wifiOnly = _wifiOnlySwitch.on;
}

- (void)videoSyncSwitchFlip:(id)sender
{
    self.videoSync = _videoSyncSwitch.on;
    [_connection photosChanged:nil];
}

- (CLLocationManager *)locationManager {
    if (!_locationManager) {
        _locationManager = [[CLLocationManager alloc] init];
        _locationManager.delegate = self;
    }
    return _locationManager;
}

- (IBAction)autoClearPasswdSwtichFlip:(id)sender
{
    _connection.autoClearRepoPasswd = _autoClearPasswdSwitch.on;
}

- (IBAction)localDecryptionSwtichFlip:(id)sender
{
    _connection.localDecryption = _localDecrySwitch.on;
}

- (IBAction)enableTouchIDSwtichFlip:(id)sender
{
    if (_enableTouchIDSwitch.on) {
        NSError *error = nil;
        LAContext *context = [[LAContext alloc] init];
        if (![context canEvaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics error:&error]) {
            Warning("TouchID unavailable: %@", error);
            [self alertWithTitle:STR_15];
            _enableTouchIDSwitch.on = false;
            return;
        }
    }
    _connection.touchIdEnabled = _enableTouchIDSwitch.on;
}

- (void)backgroundSyncSwitchFlip:(id)sender
{
    Debug("_backgroundSyncSwitch status:%d", _backgroundSyncSwitch.on);
    if (!_backgroundSyncSwitch.on) {
        self.backgroundSync = _backgroundSyncSwitch.on;
        return;
    }
    CLAuthorizationStatus status = [CLLocationManager authorizationStatus];
    Debug("AuthorizationStatus: %d", status);
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    if (status == kCLAuthorizationStatusNotDetermined) {
        if (ios8) {
            [self.locationManager requestAlwaysAuthorization];
        } else {
            [appdelegate startSignificantChangeUpdates];
        }
        return;
    }
    if (status != kCLAuthorizationStatusAuthorizedAlways) {
        [self alertWithTitle:NSLocalizedString(@"This app does not have access to your location service.", @"Seafile") message:NSLocalizedString(@"You can enable access in Privacy Settings", @"Seafile")];
        _backgroundSyncSwitch.on = false;
    } else {
        self.backgroundSync = true;
    }
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    _nameCell.textLabel.text = NSLocalizedString(@"Username", @"Seafile");
    _usedspaceCell.textLabel.text = NSLocalizedString(@"Space Used", @"Seafile");
    _enableTouchIDLabel.text = NSLocalizedString(@"Enable TouchID", @"Seafile");
    _autoCameraUploadLabel.text = NSLocalizedString(@"Auto Upload", @"Seafile");
    _videoSyncLabel.text = NSLocalizedString(@"Upload Videos", @"Seafile");
    _wifiOnlyLabel.text = NSLocalizedString(@"Wifi Only", @"Seafile");
    _backgroundSyncLable.text = NSLocalizedString(@"Background Upload", @"Seafile");
    _autoClearPasswdLabel.text = NSLocalizedString(@"Auto clear passwords", @"Auto cleay library password");
    _localDecryLabel.text = NSLocalizedString(@"Local decryption", @"Local decryption");

    _syncRepoCell.textLabel.text = NSLocalizedString(@"Upload Destination", @"Seafile");
    _cacheCell.textLabel.text = NSLocalizedString(@"Local Cache", @"Seafile");
    _wipeCacheCell.textLabel.text = NSLocalizedString(@"Wipe Cache", @"Seafile");

    _tellFriendCell.textLabel.text = [NSString stringWithFormat:NSLocalizedString(@"Tell Friends about %@", @"Seafile"), APP_NAME];
    _websiteCell.textLabel.text = NSLocalizedString(@"Website", @"Seafile");
    _websiteCell.detailTextLabel.text = @"www.seafile.com";
    _serverCell.textLabel.text = NSLocalizedString(@"Server", @"Seafile");
    _versionCell.textLabel.text = NSLocalizedString(@"Version", @"Seafile");
    _logOutLabel.text = NSLocalizedString(@"Log out", @"Seafile");
    _clearEncRepoPasswordCell.textLabel.text = NSLocalizedString(@"Clear remembered passwords", @"Seafile");
    self.title = NSLocalizedString(@"Settings", @"Seafile");

    self.navigationController.navigationBar.tintColor = BAR_COLOR;
    [_autoSyncSwitch addTarget:self action:@selector(autoSyncSwitchFlip:) forControlEvents:UIControlEventValueChanged];
    [_wifiOnlySwitch addTarget:self action:@selector(wifiOnlySwitchFlip:) forControlEvents:UIControlEventValueChanged];
    [_videoSyncSwitch addTarget:self action:@selector(videoSyncSwitchFlip:) forControlEvents:UIControlEventValueChanged];
    [_backgroundSyncSwitch addTarget:self action:@selector(backgroundSyncSwitchFlip:) forControlEvents:UIControlEventValueChanged];
    [_autoClearPasswdSwitch addTarget:self action:@selector(autoClearPasswdSwtichFlip:) forControlEvents:UIControlEventValueChanged];
    [_localDecrySwitch addTarget:self action:@selector(localDecryptionSwtichFlip:) forControlEvents:UIControlEventValueChanged];
    [_enableTouchIDSwitch addTarget:self action:@selector(enableTouchIDSwtichFlip:) forControlEvents:UIControlEventValueChanged];


    NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];
    _version = [infoDictionary objectForKey:@"CFBundleShortVersionString"];
    _versionCell.detailTextLabel.text = _version;
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    dispatch_async(dispatch_get_main_queue(), ^ {
        [self configureView];
    });
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

    _nameCell.detailTextLabel.text = _connection.username;
    _serverCell.detailTextLabel.text = [_connection.address trimUrl];
    _autoSyncSwitch.on = self.autoSync;
    if (self.autoSync)
        [self checkPhotoLibraryAuthorizationStatus];
    _wifiOnlySwitch.on = self.wifiOnly;
    _videoSyncSwitch.on = self.videoSync;
    _backgroundSyncSwitch.on = self.backgroundSync;
    SeafRepo *repo = [_connection getRepo:_connection.autoSyncRepo];
    _syncRepoCell.detailTextLabel.text = repo ? repo.name : nil;
    _autoClearPasswdSwitch.on = _connection.autoClearRepoPasswd;
    _localDecrySwitch.on = _connection.localDecryption;
    _enableTouchIDSwitch.on = _connection.touchIdEnabled;

    long long cacheSize = [self cacheSize];
    _cacheCell.detailTextLabel.text = [FileSizeFormatter stringFromLongLong:cacheSize];
    Debug("%@, %lld, %lld, total cache=%lld", _connection.username, _connection.usage, _connection.quota, cacheSize);
    if (_connection.quota <= 0) {
        if (_connection.usage < 0)
            _usedspaceCell.detailTextLabel.text = @"Unknown";
        else
            _usedspaceCell.detailTextLabel.text = [FileSizeFormatter stringFromLongLong:_connection.usage];
    } else {
        float usage = 100.0 * _connection.usage/_connection.quota;
        NSString *quotaString = [FileSizeFormatter stringFromLongLong:_connection.quota];
        if (usage < 0)
            _usedspaceCell.detailTextLabel.text = [NSString stringWithFormat:@"? of %@", quotaString];
        else
            _usedspaceCell.detailTextLabel.text = [NSString stringWithFormat:@"%.2f%% of %@", usage, quotaString];
    }
    [self.tableView reloadData];
}

- (void)updateAccountInfo
{
    [_connection getAccountInfo:^(bool result) {
        if (result) {
            dispatch_async(dispatch_get_main_queue(), ^ {
                [self configureView];
                _connection.photSyncWatcher = self;
            });
        }
    }];
}
- (void)setConnection:(SeafConnection *)connection
{
    _connection = connection;
    [self.tableView reloadData];
    [self updateAccountInfo];
}

- (void)popupRepoSelect
{
    SeafDirViewController *c = [[SeafDirViewController alloc] initWithSeafDir:self.connection.rootFolder delegate:self chooseRepo:true];
    [self.navigationController pushViewController:c animated:true];
}

#pragma mark - Table view delegate
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [self.tableView deselectRowAtIndexPath:[self.tableView indexPathForSelectedRow] animated:NO];
    if (indexPath.section == SECTION_ACCOUNT) {
        if (indexPath.row == 1) // Select the quota cell
            [self updateAccountInfo];
    } else if (indexPath.section == SECTION_CAMERA) {
        Debug("selected %ld, autoSync: %d", (long)indexPath.row, self.autoSync);
        if (indexPath.row == CELL_DESTINATION) {
            if (self.autoSync) {
                [self popupRepoSelect];
            } else {
                [self alertWithTitle:NSLocalizedString(@"Auto upload should be enabled first.", @"Seafile")];
            }
        }
    } else if (indexPath.section == SECTION_CACHE) {
        Debug("selected %ld, autoSync: %d", (long)indexPath.row, self.autoSync);
        if (indexPath.row == CELL_CACHE_SIZE) {
        } else if (indexPath.row == CELL_CACHE_WIPE) {
            [self alertWithTitle:MSG_CLEAR_CACHE message:nil yes:^{
                SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
                [(SeafDetailViewController *)[appdelegate detailViewControllerAtIndex:TABBED_SETTINGS] setPreViewItem:nil master:nil];
                [SeafGlobal.sharedObject clearCache];
                long long cacheSize = [self cacheSize];
                _cacheCell.detailTextLabel.text = [FileSizeFormatter stringFromLongLong:cacheSize];
            } no:nil];
        }
    } else if (indexPath.section == SECTION_ENC) {
        if (indexPath.row == CELL_CLEAR_PASSWORD) {
            [_connection clearRepoPasswords];
            [SVProgressHUD showSuccessWithStatus:NSLocalizedString(@"Clear libraries passwords successfully.", @"Seafile")];
        }
    } else if (indexPath.section == SECTION_ABOUT) {
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
    } else if (indexPath.section == SECTION_LOGOUT) {
        [self logOut];
    }
}

- (void)logOut
{
    [self alertWithTitle:MSG_LOG_OUT message:nil yes:^{
        Debug("Log out %@ %@", _connection.address, _connection.username);
        [_connection logout];
        SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
        [appdelegate exitAccount];
    } no:nil];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    NSString *sectionNames[] = {
        NSLocalizedString(@"Account Info", @"Seafile"),
        NSLocalizedString(@"Camera Upload", @"Seafile"),
        NSLocalizedString(@"Cache", @"Seafile"),
        NSLocalizedString(@"Encrypted Libraries", @"Seafile"),
        NSLocalizedString(@"About", @"Seafile"),
        @"",
    };
    if (section < SECTION_ACCOUNT || section > SECTION_LOGOUT)
        return nil;
    if (section == SECTION_CAMERA && _connection.inAutoSync) {
        NSUInteger num = _connection.photosInSyncing;
        NSString *remainStr = @"";
        if (num == 0) {
            remainStr = NSLocalizedString(@"All photos synced", @"Seafile");
        } else if (num == 1) {
            remainStr = NSLocalizedString(@"1 photo remain", @"Seafile");
        } else {
            remainStr = [NSString stringWithFormat:NSLocalizedString(@"%ld photos remain", @"Seafile"), num];
        }
#if DEBUG
        remainStr = [remainStr stringByAppendingFormat:@"  U:%lu D:%lu", SeafGlobal.sharedObject.uploadingnum, SeafGlobal.sharedObject.downloadingnum];
#endif
        return [sectionNames[section] stringByAppendingFormat:@"\t %@", remainStr];
    }
#if DEBUG
    else if (section == SECTION_CAMERA) {
        NSString *remainStr = [NSString stringWithFormat:@"  U:%ld D:%ld", (long)SeafGlobal.sharedObject.uploadingnum, (long)SeafGlobal.sharedObject.downloadingnum];
        return [sectionNames[section] stringByAppendingFormat:@"\t %@", remainStr];
    }
#endif
    return sectionNames[section];
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
    [mailPicker setSubject:[NSString stringWithFormat:NSLocalizedString(@"%@ invite you to %@", @"Seafile"), NSFullUserName(), APP_NAME]];
    NSString *emailBody = [NSString stringWithFormat:NSLocalizedString(@"Hey there!<br/><br/> I've been using %@ and thought you might like it. It is a free way to bring all you files anywhere and share them easily.<br/><br/>Go to the official website of %@:</br></br> <a href=\"%@\">%@</a>\n\n", @"Seafile"), APP_NAME, APP_NAME, SEAFILE_SITE, SEAFILE_SITE];

    [mailPicker setMessageBody:emailBody isHTML:YES];
}

- (void)displayMailPicker
{
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    MFMailComposeViewController *mailPicker = appdelegate.globalMailComposer;
    mailPicker.mailComposeDelegate = self;
    [self configureInvitationMail:mailPicker];
    [appdelegate.window.rootViewController presentViewController:mailPicker animated:YES completion:nil];
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
- (void)setSyncRepo:(SeafRepo *)repo
{
    _connection.autoSyncRepo = repo.repoId;
    _syncRepoCell.detailTextLabel.text = repo.name;
    [_connection performSelectorInBackground:@selector(checkAutoSync) withObject:nil];
    [self.tableView reloadData];
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    [appdelegate checkBackgroundUploadStatus];
}

- (void)setAutoSyncRepo:(SeafRepo *)repo
{
    NSString *old = _connection.autoSyncRepo;
    if ([repo.repoId isEqualToString:old]) {
        [_connection photosChanged:nil];
        return;
    }

    if (_connection.autoSyncedNum == 0) {
        return [self setSyncRepo:repo];
    }

    dispatch_async(dispatch_get_main_queue(), ^ {
        [self alertWithTitle:MSG_RESET_UPLOADED message:nil yes:^{
            [_connection resetUploadedPhotos];
            [self setSyncRepo:repo];
        } no:^{
            [self setSyncRepo:repo];
        }];
    });
}
- (void)chooseDir:(UIViewController *)c dir:(SeafDir *)dir
{
    if (c.navigationController == self.navigationController) {
        [self.navigationController popToRootViewControllerAnimated:true];
    } else {
        [c.navigationController dismissViewControllerAnimated:YES completion:nil];
    }
    SeafRepo *repo = (SeafRepo *)dir;
    Debug("Choose repo %@ for photo auto upload, encryped:%d", repo.name, repo.encrypted);
    if (repo.encrypted) {
        if (!_connection.localDecryption) {
            return [self alertWithTitle:NSLocalizedString(@"Please enable \"Local decryption\" for auto uploading photos to an encrypted library.", @"Seafile")];
        } else if (_connection.autoClearRepoPasswd) {
            return [self alertWithTitle:NSLocalizedString(@"Please disable \"Auto clear passwords\" for auto uploading photos to an encrypted library.", @"Seafile")];
        } else if (repo.passwordRequired) {
            return [self popupSetRepoPassword:repo handler:^{
                [self setAutoSyncRepo:repo];
            }];
        }
    }
    [self setAutoSyncRepo:repo];
}

- (void)cancelChoose:(UIViewController *)c
{
    if (c.navigationController == self.navigationController) {
        [self.navigationController popToRootViewControllerAnimated:true];
    } else {
        [c.navigationController dismissViewControllerAnimated:YES completion:nil];
    }
}

#pragma mark - SeafPhotoSyncWatcherDelegate
- (void)photoSyncChanged:(long)remain
{
    Debug("%ld photos remain to uplaod", remain);
    if (self.isVisible) {
        dispatch_async(dispatch_get_main_queue(), ^ {
            [self.tableView reloadData];
        });
    }
}

#pragma mark - CLLocationManagerDelegate

- (void)locationManager:(CLLocationManager *)manager didChangeAuthorizationStatus:(CLAuthorizationStatus)status
{
    Debug("AuthorizationStatus: %d", status);
    if (status != kCLAuthorizationStatusAuthorizedAlways) {
        _backgroundSyncSwitch.on = false;
    } else {
        _backgroundSyncSwitch.on = true;
        self.backgroundSync = true;
    }
}

@end
