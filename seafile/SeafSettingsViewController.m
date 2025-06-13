//
//  SeafSettingsViewController.m
//  seafile
//
//  Created by Wang Wei on 10/27/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

@import LocalAuthentication;
@import QuartzCore;
@import Photos;

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
#import "SeafBackupGuideViewController.h"

#define CELL_PADDING_HORIZONTAL 10.0
#define CELL_CORNER_RADIUS 10.0

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
    CELL_CAMERA_HEIC,
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

@interface SeafSettingsViewController ()<SeafPhotoSyncWatcherDelegate, CLLocationManagerDelegate, SeafBackupGuideDelegate>
// Holds the cell that displays the username.
@property (strong, nonatomic) IBOutlet UITableViewCell *nameCell;
// Displays the amount of space used by the user.
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

@property (strong, nonatomic) CLLocationManager *locationManager; // Manages location services for background upload functionality.

@property int state;// Stores the current state of settings options selected.

@property NSString *version;// Stores the current version of the application.
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

// Returns whether auto-sync is enabled.
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

// Sets the auto-sync feature on or off.
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

// Checks the authorization status of the photo library.
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

// Handles the toggle of the auto-sync switch.
- (void)autoSyncSwitchFlip:(id)sender
{
    if (_autoSyncSwitch.on) {
        // The block to run on success
        void (^proceed)(void) = ^{
            NSString *key = [NSString stringWithFormat:@"hasCompletedBackupGuide_%@_%@", self.connection.address, self.connection.username];
            BOOL hasCompletedGuide = [[NSUserDefaults standardUserDefaults] boolForKey:key];

            if (!self.connection.autoSyncRepo) {
                if (hasCompletedGuide) {
                    [self checkPhotoLibraryAuthorizationStatus];
                } else {
                    SeafBackupGuideViewController *guideVC = [[SeafBackupGuideViewController alloc] initWithConnection:self.connection];
                    guideVC.delegate = self;
                    guideVC.hidesBottomBarWhenPushed = YES;
                    [self.navigationController pushViewController:guideVC animated:YES];
                }
            } else {
                [self checkPhotoLibraryAuthorizationStatus];
            }
        };

        // Check permissions
        PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatus];
        if (status == PHAuthorizationStatusAuthorized) {
            proceed();
        } else if (status == PHAuthorizationStatusNotDetermined) {
            [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus newStatus) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (newStatus == PHAuthorizationStatusAuthorized) {
                        proceed();
                    } else {
                        // Denied, turn switch off
                        self->_autoSyncSwitch.on = false;
                    }
                });
            }];
        } else { // Restricted or Denied
            [self alertWithTitle:NSLocalizedString(@"This app does not have access to your photos and videos.", @"Seafile") message:NSLocalizedString(@"You can enable access in Privacy Settings", @"Seafile")];
            _autoSyncSwitch.on = false;
        }
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

// Handles the toggle of the TouchID/FaceID switch.
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

// Handles the toggle of the background sync switch.
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
    _nameCell.detailTextLabel.textColor = BAR_COLOR_ORANGE;
    _nameCell.detailTextLabel.text = NSLocalizedString(@"Switch Account", @"Seafile");
    _usedspaceCell.textLabel.text = NSLocalizedString(@"Space Used", @"Seafile");
    
    // Set table view properties to remove top separator
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    
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

    SeafDataTaskManager.sharedObject.finishBlock = ^(id<SeafTask>  _Nonnull task) {
        [self updateSyncInfo];
    };
    
    if (@available(iOS 15.0, *)) {
        UINavigationBarAppearance *barAppearance = [UINavigationBarAppearance new];
        barAppearance.backgroundColor = [UIColor whiteColor];
        
        self.navigationController.navigationBar.standardAppearance = barAppearance;
        self.navigationController.navigationBar.scrollEdgeAppearance = barAppearance;
        
        self.tableView.sectionHeaderTopPadding = 0;
    }
    
    self.tableView.backgroundColor = kPrimaryBackgroundColor;
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(uploadTaskStatusChanged:) name:@"SeafUploadTaskStatusChanged" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(uploadTaskStatusChanged:) name:@"SeafDownloadTaskStatusChanged" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(accountInfoUpdated:) 
                                                 name:@"SeafAccountInfoUpdated" 
                                               object:nil];

}

- (void)viewDidAppear:(BOOL)animated
{
    dispatch_async(dispatch_get_main_queue(), ^ {
        [self configureView];
    });
    [super viewDidAppear:animated];
    
    // If the user navigates back from the guide without saving, turn off the switch.
    if (!self.connection.autoSyncRepo) {
        self.autoSyncSwitch.on = NO;
        self.autoSync = NO;
    }
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

// Configures the view initially with current settings and updates UI components.
- (void)configureView
{
    if (!_connection)
        return;

    _nameCell.textLabel.text = _connection.name;
    
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
        // Format as "123.5KB / 5GB" instead of percentage
        NSString *usageString = [FileSizeFormatter stringFromLongLong:_connection.usage];
        NSString *quotaString = [FileSizeFormatter stringFromLongLong:_connection.quota];
        _usedspaceCell.detailTextLabel.text = [NSString stringWithFormat:@"%@ / %@", usageString, quotaString];
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
    
    self.enableUploadHeic.on = _connection.isUploadHeicEnabled;

    [self updateSyncInfo];

    [self.tableView reloadData];
}

// Updates the upload and download tasks information.
-(void)updateSyncInfo{
    SeafAccountTaskQueue *accountTaskQueue= [SeafDataTaskManager.sharedObject accountQueueForConnection:self.connection];
    NSUInteger uploadingNum = accountTaskQueue.getOngoingTasks.count;
    NSUInteger downloadingNum = accountTaskQueue.getOngoingDownloadTasks.count;

    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.tableView.dragging == false && self.tableView.decelerating == false && self.tableView.tracking == false) {
            _downloadingCell.detailTextLabel.text = [NSString stringWithFormat:@"%lu",(long)downloadingNum];
            _uploadingCell.detailTextLabel.text = [NSString stringWithFormat:@"%lu",(long)uploadingNum];
        }
    });
}

// Fetches and updates the account information.
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

// Sets the current connection and updates the UI.
- (void)setConnection:(SeafConnection *)connection
{
    _connection = connection;
    [self.tableView reloadData];
    [self updateAccountInfo];
}

// Presents the repository selection view.
- (void)popupRepoChoose:(SeafDirChoose)choose cancel:(SeafDirCancelChoose)cancel
{
    SeafDirViewController *c = [[SeafDirViewController alloc] initWithSeafDir:self.connection.rootFolder dirChosen:choose cancel:cancel chooseRepo:true];
    c.operationState = OPERATION_STATE_OTHER;
    [self.navigationController pushViewController:c animated:true];
}

- (void)uploadTaskStatusChanged:(NSNotification *)notification {
        dispatch_async(dispatch_get_main_queue(), ^{
        // update the number of uploading and downloading
        [self updateSyncInfo];
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:SECTION_CAMERA] withRowAnimation:UITableViewRowAnimationNone];
    });
}

- (void)accountInfoUpdated:(NSNotification *)notification
{
    SeafConnection *connection = notification.object;
    BOOL success = [notification.userInfo[@"success"] boolValue];
    
    // Only update if this is the currently displayed account
    if (success && connection == self.connection && self.isVisible) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self configureView];
        });
    }
}

#pragma mark - Table view delegate

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    // Ensure cell and content view are clear to show the custom background
    cell.backgroundColor = [UIColor clearColor];
    cell.contentView.backgroundColor = [UIColor clearColor];
    // Set selection style to none to remove the highlighting effect when tapped
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    // For all cells, apply indentation
    cell.indentationLevel = 1;  // Each indentation level is typically 10 points
    cell.indentationWidth = 30; // Override the default width

    // Check if this is the logout cell or the privacy policy cell
    if (indexPath.section == SECTION_LOGOUT || 
        (indexPath.section == SECTION_ABOUT && indexPath.row == CELL_PRIVACY)) {
        // Create a custom accessory view with the chevron shifted 5px to the left
        // Instead of using the standard accessory type
        cell.accessoryType = UITableViewCellAccessoryNone;
        
        // Create a custom view for the accessory
        UIView *customAccessoryView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 15, 20)];
        
        // Create a chevron image view
        UIImageView *chevronImageView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right"]];
        if (chevronImageView.image == nil) {
            // Fallback for older iOS versions
            chevronImageView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"arrowright2"]];
        }
        
        // Set the frame to position it 5px to the left with smaller dimensions
        chevronImageView.frame = CGRectMake(-5, 2, 12, 16); // Reduced size from 15x20 to 12x16
        chevronImageView.contentMode = UIViewContentModeScaleAspectFit;
        chevronImageView.tintColor = [UIColor lightGrayColor];
        
        [customAccessoryView addSubview:chevronImageView];
        cell.accessoryView = customAccessoryView;
        
        // Only set the specific logout styling for the logout cell
        if (indexPath.section == SECTION_LOGOUT) {
            // Ensure the logout text is set properly
            cell.textLabel.text = NSLocalizedString(@"Log out", @"Seafile");
            cell.textLabel.textAlignment = NSTextAlignmentLeft;
            cell.textLabel.textColor = BAR_COLOR_ORANGE;
            // Reduce the font size
//            cell.textLabel.font = [UIFont systemFontOfSize:16.0]; // Smaller font size
        }
    } else {
        // For other cells, add the spacer accessory view
        UIView *spacerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 5, 1)];
        spacerView.backgroundColor = [UIColor clearColor];
        cell.accessoryView = spacerView;
        cell.accessoryType = UITableViewCellAccessoryNone;
    }

    // Define vertical padding (minimal, just for visual separation if needed)
    CGFloat verticalPadding = 0; // Remove extra vertical padding
    CGFloat bottomPadding = 0;

    // Remove previous custom background view if reusing cell
    UIView *existingBackground = [cell viewWithTag:999];
    [existingBackground removeFromSuperview];
    
    // Remove any existing separator view
    UIView *existingSeparator = [cell viewWithTag:888];
    [existingSeparator removeFromSuperview];

    // Create the card background view
    UIView *cardBackgroundView = [[UIView alloc] init];
    cardBackgroundView.tag = 999;
    cardBackgroundView.backgroundColor = [UIColor whiteColor]; // Card color
    cardBackgroundView.layer.cornerRadius = CELL_CORNER_RADIUS;
    cardBackgroundView.clipsToBounds = YES;

    // Determine corners to round
    NSInteger numberOfRowsInSection = [tableView numberOfRowsInSection:indexPath.section];
    BOOL isFirstCell = (indexPath.row == 0);
    BOOL isLastCell = (indexPath.row == numberOfRowsInSection - 1);

    if (isFirstCell && isLastCell) {
        cardBackgroundView.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner | kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
    } else if (isFirstCell) {
        cardBackgroundView.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    } else if (isLastCell) {
        cardBackgroundView.layer.maskedCorners = kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
    } else {
        cardBackgroundView.layer.cornerRadius = 0; // No rounding for middle cells
    }

    // Calculate frame relative to cell bounds with horizontal padding
    // Make height almost full cell height
    CGRect cardFrame = CGRectMake(CELL_PADDING_HORIZONTAL,
                                0, // Start at the top
                                cell.bounds.size.width - (2 * CELL_PADDING_HORIZONTAL),
                                cell.bounds.size.height); // Fill height

    cardBackgroundView.frame = cardFrame;
    cardBackgroundView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    // Insert the custom background view BELOW the cell's content view
    [cell insertSubview:cardBackgroundView belowSubview:cell.contentView];

    // Add separator line for all cells except the last one in each section
    if (!isLastCell) {
        // Create a separator view
        UIView *separatorView = [[UIView alloc] init];
        separatorView.tag = 888;
        separatorView.backgroundColor = [UIColor colorWithRed:0.9 green:0.9 blue:0.9 alpha:1.0]; // Light gray color
        
        // Calculate separator frame - place it at the bottom of the cell
        CGFloat separatorHeight = 0.5; // Standard separator height
        CGFloat leftInset = CELL_PADDING_HORIZONTAL + 15.0;
        CGRect separatorFrame = CGRectMake(leftInset,
                                        cell.bounds.size.height - separatorHeight,
                                        cell.bounds.size.width - leftInset - CELL_PADDING_HORIZONTAL,
                                        separatorHeight);
        
        separatorView.frame = separatorFrame;
        separatorView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
        
        // Add the separator on top of the card background but below content view
        [cell insertSubview:separatorView aboveSubview:cardBackgroundView];
    }

    // Manage Separators - hide default separators
    cell.separatorInset = UIEdgeInsetsMake(0, 0, 0, cell.bounds.size.width);
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    // Keep existing selection logic, but deselect visually immediately
    // The visual feedback comes from the row action itself (navigation, alert, etc.)
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == SECTION_ACCOUNT) {
        if (indexPath.row == 0) {
            Debug("Switch Account");
            UIStoryboard *startStoryboard = [UIStoryboard storyboardWithName:@"SeafStart" bundle:nil];
            UINavigationController *navController = [startStoryboard instantiateInitialViewController];
            StartViewController *startVC = (StartViewController *)navController.topViewController;
            startVC.hidesBottomBarWhenPushed = YES;
            
            if (IsIpad()) {
                // Configure modal presentation style for iPad
                navController.modalPresentationStyle = UIModalPresentationFormSheet;
                
                // Configure navigation bar appearance
                navController.navigationBar.tintColor = BAR_COLOR;
                navController.navigationBar.barTintColor = [UIColor whiteColor];
                navController.navigationBar.translucent = NO;
                
                if (@available(iOS 15.0, *)) {
                    UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
                    [appearance configureWithOpaqueBackground];
                    appearance.backgroundColor = [UIColor whiteColor];
                    navController.navigationBar.standardAppearance = appearance;
                    navController.navigationBar.scrollEdgeAppearance = appearance;
                }
                
                // Present the new view controller after dismissing any existing one
                dispatch_async(dispatch_get_main_queue(), ^ {
                    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
                    [appdelegate.window.rootViewController presentViewController:navController animated:YES completion:nil];
                });
            } else {
                [self.navigationController pushViewController:startVC animated:YES];
            }
        } else if (indexPath.row == 1) {// Select the quota cell
            [self updateAccountInfo];
        }
    } else if (indexPath.section == SECTION_CAMERA) {
        Debug("selected %ld, autoSync: %d", (long)indexPath.row, self.autoSync);
        if (indexPath.row == CELL_CAMERA_DESTINATION) {
            if (self.autoSync) {
                [self popupRepoChoose:^(UIViewController *c, SeafDir *dir) {
                    SeafRepo *repo = (SeafRepo *)dir;
                    Debug("Choose repo %@ for photo auto upload, encryped:%d", repo.name, repo.encrypted);
                    if (repo.encrypted) {
                        return;
                    } else {
                        [self dismissViewController:c];
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
        NSString *remainStr = @"";
        if (_connection.isCheckingPhotoLibrary) {
            remainStr = NSLocalizedString(@"Prepare for backup", @"Seafile");
        } else {
            NSUInteger num = _connection.photosInSyncing;
            if (num == 0) {
                remainStr = NSLocalizedString(@"All photos synced", @"Seafile");
            } else if (num == 1) {
                remainStr = NSLocalizedString(@"1 photo remain", @"Seafile");
            } else {
                remainStr = [NSString stringWithFormat:NSLocalizedString(@"%ld photos remain", @"Seafile"), num];
            }
#if DEBUG
//            remainStr = [remainStr stringByAppendingFormat:@" /uploading count is %ld", _connection.photoBackup.photosInUploadingArray];
#endif
        }
        return [sectionNames[section] stringByAppendingFormat:@"\t %@", remainStr];
    }
    return sectionNames[section];
}

// Custom header view with 30-point left indentation for the title
- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    // First get the title from the standard method
    NSString *title = [self tableView:tableView titleForHeaderInSection:section];
    if (!title || [title isEqualToString:@""]) {
        return nil;
    }
    
    // Create a custom header view
    UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.frame.size.width, 35)];
    headerView.backgroundColor = [UIColor clearColor];
    
    // Create a label with 30-point left indentation
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(30, 5, tableView.frame.size.width - 40, 30)];
    titleLabel.font = [UIFont systemFontOfSize:14];
    titleLabel.textColor = [UIColor colorWithWhite:0.4 alpha:1.0]; // Gray text
    titleLabel.text = title;
    [headerView addSubview:titleLabel];
    
    return headerView;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section 
{
    NSString *title = [self tableView:tableView titleForHeaderInSection:section];
    if (!title || [title isEqualToString:@""]) {
        return 12; // Small height for empty header
    }
    return 35; // Standard height for headers with titles
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
        return;
    }
    
    if (!_connection.photoBackup){
        _connection.photoBackup = [[SeafPhotoBackupTool alloc] initWithConnection:_connection andLocalUploadDir:_connection.localUploadDir];
    }
    
    [_connection resetUploadedPhotos];

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
            [self updateSyncInfo];
            // Update header view text instead of reloading the whole section
            // This avoids potential visual glitches with cell styling updates
             [self.tableView beginUpdates];
             [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:SECTION_CAMERA] withRowAnimation:UITableViewRowAnimationNone];
             [self.tableView endUpdates];
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

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"SeafUploadTaskStatusChanged" object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"SeafAccountInfoUpdated" object:nil];
}

#pragma mark - SeafBackupGuideDelegate
- (void)backupGuide:(SeafBackupGuideViewController *)guideVC didFinishWithRepo:(SeafRepo *)repo {
    [self.navigationController popToViewController:self animated:YES];
    [self setAutoSyncRepo:repo];
    [self checkPhotoLibraryAuthorizationStatus];
}

- (void)backupGuideDidCancel:(SeafBackupGuideViewController *)guideVC {
    [self.navigationController popToViewController:self animated:YES];
    _autoSyncSwitch.on = false;
    self.autoSync = false;
}

@end
