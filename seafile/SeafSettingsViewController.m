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
#import "SeafSyncInfoViewController.h"
#import "SeafRepos.h"
#import "SeafAvatar.h"
#import "SeafStorage.h"
#import "SeafDataTaskManager.h"

#import "UIViewController+Extend.h"
#import "FileSizeFormatter.h"
#import "ExtentedString.h"
#import "Debug.h"
#import "SeafPrivacyPolicyViewController.h"


enum {
    SECTION_ACCOUNT = 0,
    SECTION_CAMERA,
    SECTION_UPDOWNLOAD,
    SECTION_CACHE,
    SECTION_ENC,
    SECTION_ABOUT,
    SECTION_LOGOUT,
};

enum CAMERA_CELL{
    CELL_CAMERA_AUTO = 0,
    CELL_CAMERA_VIDEOS,
    CELL_CAMERA_WIFIONLY,
    CELL_CAMERA_BACKGROUND,
    CELL_CAMERA_DESTINATION,
    CELL_CAMERA_UPLOADING,
};

enum UPDOWNLOAD_CELL{
    CELL_DOWNLOAD = 0,
    CELL_UPLOAD = 1,

};

enum {
    CELL_CACHE_SIZE = 0,
    CELL_CACHE_WIPE,
};

enum ENC_LIBRARIES{
    CELL_CLEAR_PASSWORD = 0,
};

enum {
    CELL_SERVER = 0,
    CELL_VERSION,
    CELL_PRIVACY,
};

#define MSG_RESET_UPLOADED NSLocalizedString(@"Do you want reset the uploaded photos?", @"Seafile")
#define MSG_CLEAR_CACHE NSLocalizedString(@"Are you sure to clear all the cache?", @"Seafile")
#define MSG_LOG_OUT NSLocalizedString(@"Are you sure to log out?", @"Seafile")

@interface SeafSettingsViewController ()<SeafPhotoSyncWatcherDelegate, CLLocationManagerDelegate>
@property (strong, nonatomic) IBOutlet UITableViewCell *nameCell;
@property (strong, nonatomic) IBOutlet UITableViewCell *usedspaceCell;
@property (strong, nonatomic) IBOutlet UITableViewCell *serverCell;
@property (strong, nonatomic) IBOutlet UITableViewCell *cacheCell;
@property (strong, nonatomic) IBOutlet UITableViewCell *versionCell;
@property (strong, nonatomic) IBOutlet UITableViewCell *autoSyncCell;
@property (strong, nonatomic) IBOutlet UITableViewCell *syncRepoCell;
@property (strong, nonatomic) IBOutlet UITableViewCell *videoSyncCell;
@property (strong, nonatomic) IBOutlet UITableViewCell *backgroundSyncCell;
@property (strong, nonatomic) IBOutlet UITableViewCell *clearEncRepoPasswordCell;
@property (strong, nonatomic) IBOutlet UITableViewCell *wipeCacheCell;
@property (weak, nonatomic) IBOutlet UITableViewCell *uploadingCell;
@property (weak, nonatomic) IBOutlet UITableViewCell *downloadingCell;

@property (strong, nonatomic) IBOutlet UILabel *logOutLabel;
@property (strong, nonatomic) IBOutlet UILabel *autoCameraUploadLabel;
@property (strong, nonatomic) IBOutlet UILabel *wifiOnlyLabel;
@property (strong, nonatomic) IBOutlet UILabel *videoSyncLabel;
@property (strong, nonatomic) IBOutlet UILabel *backgroundSyncLable;
@property (strong, nonatomic) IBOutlet UILabel *autoClearPasswdLabel;
@property (strong, nonatomic) IBOutlet UILabel *localDecryLabel;
@property (strong, nonatomic) IBOutlet UILabel *enableTouchIDLabel;
@property (weak, nonatomic) IBOutlet UILabel *privacyPolicyLabel;

@property (strong, nonatomic) IBOutlet UISwitch *autoSyncSwitch;
@property (strong, nonatomic) IBOutlet UISwitch *wifiOnlySwitch;
@property (strong, nonatomic) IBOutlet UISwitch *videoSyncSwitch;
@property (strong, nonatomic) IBOutlet UISwitch *backgroundSyncSwitch;
@property (strong, nonatomic) IBOutlet UISwitch *autoClearPasswdSwitch;
@property (strong, nonatomic) IBOutlet UISwitch *localDecrySwitch;
@property (strong, nonatomic) IBOutlet UISwitch *enableTouchIDSwitch;
@property (weak, nonatomic) IBOutlet UISwitch *enableUploadHeic;
@property (weak, nonatomic) IBOutlet UILabel *enableHeicLabel;

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
    Debug("Current AuthorizationStatus:%ld", (long)[PHPhotoLibrary authorizationStatus]);

    if([PHPhotoLibrary authorizationStatus] == PHAuthorizationStatusNotDetermined) {
        [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (status == PHAuthorizationStatusAuthorized) {
                    self.autoSync = _autoSyncSwitch.on;
                } else {
                    _autoSyncSwitch.on = false;
                }
            });
        }];
    } else if([PHPhotoLibrary authorizationStatus] == PHAuthorizationStatusRestricted ||
              [PHPhotoLibrary authorizationStatus] == PHAuthorizationStatusDenied) {
        [self alertWithTitle:NSLocalizedString(@"This app does not have access to your photos and videos.", @"Seafile") message:NSLocalizedString(@"You can enable access in Privacy Settings", @"Seafile")];
        _autoSyncSwitch.on = false;
    } else if([PHPhotoLibrary authorizationStatus] == PHAuthorizationStatusAuthorized) {
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
    _connection.localDecryptionEnabled = _localDecrySwitch.on;
}
- (IBAction)enableUploadHeicFlip:(UISwitch *)sender {
    [_connection setUploadHeicEnabled:sender.on];
}

- (IBAction)enableTouchIDSwtichFlip:(id)sender
{
    if (_enableTouchIDSwitch.on) {
        NSError *error = nil;
        LAContext *context = [[LAContext alloc] init];
        if (![context canEvaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics error:&error]) {
            Warning("TouchID unavailable: %@", error);
            if (@available(iOS 11.0, *)) {
                if (context.biometryType == LABiometryTypeFaceID) {
                    [self alertWithTitle:STR_19];
                } else {
                    [self alertWithTitle:STR_15];
                }
            } else {
                [self alertWithTitle:STR_15];
            }
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
    
    LAContext *lac = [[LAContext alloc] init];
    if (@available(iOS 11.0, *)) {
        if (lac.biometryType == LABiometryTypeFaceID) {
            _enableTouchIDLabel.text = NSLocalizedString(@"Enable FaceID", @"Seafile");
        } else {
            _enableTouchIDLabel.text = NSLocalizedString(@"Enable TouchID", @"Seafile");
        }
    } else {
        _enableTouchIDLabel.text = NSLocalizedString(@"Enable TouchID", @"Seafile");
    }
    _autoCameraUploadLabel.text = NSLocalizedString(@"Auto Upload", @"Seafile");
    _videoSyncLabel.text = NSLocalizedString(@"Upload Videos", @"Seafile");
    _wifiOnlyLabel.text = NSLocalizedString(@"Wifi Only", @"Seafile");
    _backgroundSyncLable.text = NSLocalizedString(@"Background Upload", @"Seafile");
    _syncRepoCell.textLabel.text = NSLocalizedString(@"Upload Destination", @"Seafile");
    _enableHeicLabel.text = NSLocalizedString(@"Upload HEIC", @"Seafile");

    _downloadingCell.textLabel.text = NSLocalizedString(@"Downloading", @"Seafile");
    _uploadingCell.textLabel.text = NSLocalizedString(@"Uploading", @"Seafile");

    _cacheCell.textLabel.text = NSLocalizedString(@"Local Cache", @"Seafile");
    _wipeCacheCell.textLabel.text = NSLocalizedString(@"Wipe Cache", @"Seafile");

    _clearEncRepoPasswordCell.textLabel.text = NSLocalizedString(@"Clear remembered passwords", @"Seafile");
    _autoClearPasswdLabel.text = NSLocalizedString(@"Auto clear passwords", @"Auto cleay library password");
    _localDecryLabel.text = NSLocalizedString(@"Local decryption", @"Local decryption");

    _serverCell.textLabel.text = NSLocalizedString(@"Server", @"Seafile");
    _versionCell.textLabel.text = NSLocalizedString(@"Version", @"Seafile");
    _logOutLabel.text = NSLocalizedString(@"Log out", @"Seafile");
    _privacyPolicyLabel.text = NSLocalizedString(@"Privacy Policy", @"Seafile");

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
    [self configureView];

    SeafDataTaskManager.sharedObject.trySyncBlock = ^(id<SeafTask>  _Nonnull task) {
        [self performSelectorInBackground:@selector(updateSyncInfo) withObject:nil];
    };
    SeafDataTaskManager.sharedObject.finishBlock = ^(id<SeafTask>  _Nonnull task) {
        [self performSelectorInBackground:@selector(updateSyncInfo) withObject:nil];
    };
    
    if (@available(iOS 15.0, *)) {
        UINavigationBarAppearance *barAppearance = [UINavigationBarAppearance new];
        barAppearance.backgroundColor = [UIColor whiteColor];
        
        self.navigationController.navigationBar.standardAppearance = barAppearance;
        self.navigationController.navigationBar.scrollEdgeAppearance = barAppearance;
        
        self.tableView.sectionHeaderTopPadding = 0;
    }
}

- (void)viewDidAppear:(BOOL)animated
{
    dispatch_async(dispatch_get_main_queue(), ^ {
        [self configureView];
    });
    [super viewDidAppear:animated];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)configureView
{
    if (!_connection)
        return;

    _nameCell.detailTextLabel.text = _connection.username;
    _enableTouchIDSwitch.on = _connection.touchIdEnabled;

    Debug("Account : %@, %lld, quota: %lld", _connection.username, _connection.usage, _connection.quota);
    long long cacheSize = [SeafStorage.sharedObject cacheSize];
    Debug("Total cache: %lld", cacheSize);
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

    _autoSyncSwitch.on = self.autoSync;
    if (self.autoSync)
        [self checkPhotoLibraryAuthorizationStatus];
    _videoSyncSwitch.on = self.videoSync;
    _wifiOnlySwitch.on = self.wifiOnly;
    _backgroundSyncSwitch.on = self.backgroundSync;
    SeafRepo *cameraRepo = [_connection getRepo:_connection.autoSyncRepo];
    _syncRepoCell.detailTextLabel.text = cameraRepo ? cameraRepo.name : nil;

    _cacheCell.detailTextLabel.text = [FileSizeFormatter stringFromLongLong:cacheSize];

    _autoClearPasswdSwitch.on = _connection.autoClearRepoPasswd;
    _localDecrySwitch.on = _connection.localDecryptionEnabled;
    _serverCell.detailTextLabel.text = [_connection.address trimUrl];
    
    self.enableUploadHeic.on = _connection.uploadHeicEnabled;

    [self updateSyncInfo];

    [self.tableView reloadData];
}

-(void)updateSyncInfo{
    NSInteger downloadingNum = [[SeafDataTaskManager.sharedObject accountQueueForConnection:self.connection].fileQueue taskNumber];
    NSInteger uploadingNum = [[SeafDataTaskManager.sharedObject accountQueueForConnection:self.connection].uploadQueue taskNumber];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.tableView.dragging == false && self.tableView.decelerating == false && self.tableView.tracking == false) {
            _downloadingCell.detailTextLabel.text = [NSString stringWithFormat:@"%lu",(long)downloadingNum];
            _uploadingCell.detailTextLabel.text = [NSString stringWithFormat:@"%lu",(long)uploadingNum];
        }
    });
}

- (void)updateAccountInfo
{
    [_connection getAccountInfo:^(bool result) {
        if (result) {
            dispatch_async(dispatch_get_main_queue(), ^ {
                if (self.isVisible) {
                    [self configureView];
                }
            });
        }
    }];
}
- (void)setConnection:(SeafConnection *)connection
{
    _connection = connection;
    _connection.photSyncWatcher = self;
    [self.tableView reloadData];
    [self updateAccountInfo];
}

- (void)popupRepoChoose:(SeafDirChoose)choose cancel:(SeafDirCancelChoose)cancel
{
    SeafDirViewController *c = [[SeafDirViewController alloc] initWithSeafDir:self.connection.rootFolder dirChosen:choose cancel:cancel chooseRepo:true];
    c.operationState = OPERATION_STATE_OTHER;
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
        if (indexPath.row == CELL_CAMERA_DESTINATION) {
            if (self.autoSync) {
                [self popupRepoChoose:^(UIViewController *c, SeafDir *dir) {
                    [self dismissViewController:c];
                    SeafRepo *repo = (SeafRepo *)dir;
                    Debug("Choose repo %@ for photo auto upload, encryped:%d", repo.name, repo.encrypted);
                    if (repo.encrypted) {
                        if (!_connection.localDecryptionEnabled) {
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
                } cancel:^(UIViewController *c) {
                    [self dismissViewController:c];
                }];
            } else {
                [self alertWithTitle:NSLocalizedString(@"Auto upload should be enabled first.", @"Seafile")];
            }
        }
    } else if (indexPath.section == SECTION_UPDOWNLOAD) {
        Debug("selected %ld, autoSync: %d", (long)indexPath.row, self.autoSync);
        if (indexPath.row == CELL_UPLOAD) {
            SeafSyncInfoViewController *syncInfoVC = [[SeafSyncInfoViewController alloc] initWithType:UPLOAD_DETAIL];
            syncInfoVC.hidesBottomBarWhenPushed = YES;
            [self.navigationController pushViewController:syncInfoVC animated:YES];
        } else if (indexPath.row == CELL_DOWNLOAD) {
            SeafSyncInfoViewController *syncInfoVC = [[SeafSyncInfoViewController alloc] initWithType:DOWNLOAD_DETAIL];
            syncInfoVC.hidesBottomBarWhenPushed = YES;
            [self.navigationController pushViewController:syncInfoVC animated:YES];
        }
    } else if (indexPath.section == SECTION_CACHE) {
        Debug("selected %ld, autoSync: %d", (long)indexPath.row, self.autoSync);
        if (indexPath.row == CELL_CACHE_SIZE) {
        } else if (indexPath.row == CELL_CACHE_WIPE) {
            [self alertWithTitle:MSG_CLEAR_CACHE message:nil yes:^{
                SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
                [(SeafDetailViewController *)[appdelegate detailViewControllerAtIndex:TABBED_SETTINGS] setPreViewItem:nil master:nil];
                [_connection clearAccountCache];
                long long cacheSize = [SeafStorage.sharedObject cacheSize];
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
            case CELL_SERVER:
                [[UIApplication sharedApplication] openURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/", _connection.address]]];
                break;
            case CELL_PRIVACY:
                [self privacyPolicyVC];
                break;
            default:
                break;
        }
    } else if (indexPath.section == SECTION_LOGOUT) {
        [self logOut];
    }
}

- (void)privacyPolicyVC {
    SeafPrivacyPolicyViewController *vc = [[SeafPrivacyPolicyViewController alloc] init];
    if (IsIpad()) {
        SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
        [appdelegate showDetailView:vc];
    } else {
        vc.hidesBottomBarWhenPushed = true;
        [self.navigationController pushViewController:vc animated:true];
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
        NSLocalizedString(@"Upload & Download", @"Seafile"),
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
        return [sectionNames[section] stringByAppendingFormat:@"\t %@", remainStr];
    }
#if DEBUG
    else if (section == SECTION_CAMERA) {
        NSInteger downloadingNum = [[SeafDataTaskManager.sharedObject accountQueueForConnection:self.connection].fileQueue taskNumber];
        NSInteger uploadingNum = [[SeafDataTaskManager.sharedObject accountQueueForConnection:self.connection].uploadQueue taskNumber];
        NSString *remainStr = [NSString stringWithFormat:@"  U:%lu D:%lu",(long)uploadingNum,(long)downloadingNum];
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

#pragma mark - SeafDirDelegate
- (void)setSyncRepo:(SeafRepo *)repo
{
    _connection.autoSyncRepo = repo.repoId;
    _syncRepoCell.detailTextLabel.text = repo.name;
    [_connection performSelectorInBackground:@selector(checkAutoSync) withObject:nil];
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    [appdelegate checkBackgroundUploadStatus];
}

- (void)setAutoSyncRepo:(SeafRepo *)repo
{
    NSString *old = _connection.autoSyncRepo;
    if ([repo.repoId isEqualToString:old]) {
        [_connection photosDidChange:nil];
        return;
    }

    if (_connection.autoSyncedNum > 0) {
        [_connection resetUploadedPhotos];
    }

    dispatch_async(dispatch_get_main_queue(), ^ {
        [self setSyncRepo:repo];
    });
}

- (void)dismissViewController:(UIViewController *)c
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
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.isVisible) {
            [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:SECTION_CAMERA] withRowAnimation:UITableViewRowAnimationNone];
        }
    });
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
