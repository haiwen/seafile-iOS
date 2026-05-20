//
//  SeafImagePickerHelper.m
//  seafile
//

#import "SeafImagePickerHelper.h"
#import "Constants.h"
#import "Debug.h"
#import <PhotosUI/PhotosUI.h>
#import <PhotosUI/PHPhotoLibrary+PhotosUISupport.h>

@interface SeafImagePickerHelper ()
@property (nonatomic, weak) UIViewController *presentingVC;
@end

@implementation SeafImagePickerHelper

- (instancetype)init
{
    self = [super init];
    if (self) {
        _allowsMultipleSelection = YES;
        _mediaType = QBImagePickerMediaTypeImage;
        _maximumNumberOfSelection = 0;
    }
    return self;
}

#pragma mark - Public

- (void)presentFromViewController:(UIViewController *)vc
                    barButtonItem:(UIBarButtonItem *)barItem
                       sourceView:(UIView *)sourceView
{
    self.presentingVC = vc;

    PHAuthorizationStatus status;
    if (@available(iOS 14, *)) {
        status = [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelReadWrite];
    } else {
        status = [PHPhotoLibrary authorizationStatus];
    }

    switch (status) {
        case PHAuthorizationStatusNotDetermined: {
            void (^completion)(PHAuthorizationStatus) = ^(PHAuthorizationStatus newStatus) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self presentFromViewController:vc barButtonItem:barItem sourceView:sourceView];
                });
            };
            if (@available(iOS 14, *)) {
                [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelReadWrite handler:completion];
            } else {
                [PHPhotoLibrary requestAuthorization:completion];
            }
            return;
        }
        case PHAuthorizationStatusRestricted:
        case PHAuthorizationStatusDenied:
            [self showPermissionDeniedAlertFromViewController:vc];
            return;
        case PHAuthorizationStatusLimited:
        case PHAuthorizationStatusAuthorized:
        default:
            [self presentQBImagePickerFromViewController:vc barButtonItem:barItem sourceView:sourceView];
            return;
    }
}

#pragma mark - Private

- (void)presentQBImagePickerFromViewController:(UIViewController *)vc
                                 barButtonItem:(UIBarButtonItem *)barItem
                                    sourceView:(UIView *)sourceView
{
    QBImagePickerController *picker = [[QBImagePickerController alloc] init];
    picker.title = NSLocalizedString(@"Photos", @"Seafile");
    picker.delegate = self;
    picker.allowsMultipleSelection = self.allowsMultipleSelection;
    picker.mediaType = self.mediaType;
    if (self.maximumNumberOfSelection > 0) {
        picker.maximumNumberOfSelection = self.maximumNumberOfSelection;
    }

    // Theme: match Seafile app style
    picker.tintColor          = BAR_COLOR;
    picker.checkmarkTintColor = SEAF_COLOR_ORANGE;
    picker.addPhotosTintColor = [UIColor colorWithWhite:153.0/255.0 alpha:1.0];
    picker.addPhotosIconImage = [UIImage imageNamed:@"qb_add_photo"];
    picker.backIndicatorImage = [UIImage imageNamed:@"arrowLeft_black"];

    // Show "Add Photos" cell when access is Limited
    if (@available(iOS 14, *)) {
        PHAuthorizationStatus currentStatus = [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelReadWrite];
        picker.showsAddPhotosCell = (currentStatus == PHAuthorizationStatusLimited);
    }

    if (IsIpad()) {
        picker.modalPresentationStyle = UIModalPresentationPopover;
        if (barItem) {
            picker.popoverPresentationController.barButtonItem = barItem;
        } else if (sourceView) {
            picker.popoverPresentationController.sourceView = sourceView;
            picker.popoverPresentationController.sourceRect = sourceView.bounds;
        } else {
            picker.popoverPresentationController.sourceView = vc.view;
            picker.popoverPresentationController.sourceRect = CGRectMake(vc.view.bounds.size.width / 2,
                                                                         vc.view.bounds.size.height / 2,
                                                                         0, 0);
        }
    } else {
        picker.modalPresentationStyle = UIModalPresentationFullScreen;
    }

    [vc presentViewController:picker animated:YES completion:nil];
}

- (void)showPermissionDeniedAlertFromViewController:(UIViewController *)vc
{
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:nil
                         message:NSLocalizedString(@"This app does not have access to your photos and videos.", @"Seafile")
                  preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction
        actionWithTitle:NSLocalizedString(@"Cancel", @"Seafile")
                  style:UIAlertActionStyleCancel
                handler:nil]];

    [alert addAction:[UIAlertAction
        actionWithTitle:NSLocalizedString(@"Settings", @"Seafile")
                  style:UIAlertActionStyleDefault
                handler:^(UIAlertAction * _Nonnull action) {
        NSURL *url = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
        if (url && [[UIApplication sharedApplication] canOpenURL:url]) {
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        }
    }]];

    [vc presentViewController:alert animated:YES completion:nil];
}

#pragma mark - QBImagePickerControllerDelegate

- (void)qb_imagePickerController:(QBImagePickerController *)imagePickerController
         didFinishPickingAssets:(NSArray *)assets
{
    UIViewController *vc = self.presentingVC;
    if (vc) {
        [vc dismissViewControllerAnimated:YES completion:nil];
    }
    if ([self.delegate respondsToSelector:@selector(imagePickerHelper:didFinishPickingAssets:)]) {
        [self.delegate imagePickerHelper:self didFinishPickingAssets:assets];
    }
}

- (void)qb_imagePickerControllerDidCancel:(QBImagePickerController *)imagePickerController
{
    UIViewController *vc = self.presentingVC;
    if (vc) {
        [vc dismissViewControllerAnimated:YES completion:nil];
    }
    if ([self.delegate respondsToSelector:@selector(imagePickerHelperDidCancel:)]) {
        [self.delegate imagePickerHelperDidCancel:self];
    }
}

- (void)qb_imagePickerControllerDidTapAddPhotos:(QBImagePickerController *)imagePickerController
{
    if (@available(iOS 14, *)) {
        [[PHPhotoLibrary sharedPhotoLibrary] presentLimitedLibraryPickerFromViewController:imagePickerController];
    }
}

@end
