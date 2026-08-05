//
//  SeafImagePickerHelper.m
//  seafile
//

#import "SeafImagePickerHelper.h"
#import "Constants.h"
#import "Utils.h"
#import "Debug.h"
#import "SeafStorage.h"
#import <PhotosUI/PhotosUI.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "SVProgressHUD.h"

@interface SeafImagePickerHelper () <PHPickerViewControllerDelegate>
@property (nonatomic, weak) UIViewController *presentingVC;
@end

@implementation SeafImagePickerHelper

- (instancetype)init
{
    self = [super init];
    if (self) {
        _allowsMultipleSelection = YES;
        _mediaType = SeafImagePickerMediaTypeImage;
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
    // PHPicker can grant per-selection access via NSItemProvider without
    // Photo Library permission. Do not block presentation on authorization.
    [self presentPHPickerFromViewController:vc barButtonItem:barItem sourceView:sourceView];
}

#pragma mark - Private

- (PHPickerFilter *)pickerFilter
{
    switch (self.mediaType) {
        case SeafImagePickerMediaTypeVideo:
            return [PHPickerFilter videosFilter];
        case SeafImagePickerMediaTypeAny:
            return [PHPickerFilter anyFilterMatchingSubfilters:@[
                [PHPickerFilter imagesFilter],
                [PHPickerFilter videosFilter],
            ]];
        case SeafImagePickerMediaTypeImage:
        default:
            return [PHPickerFilter imagesFilter];
    }
}

- (void)presentPHPickerFromViewController:(UIViewController *)vc
                            barButtonItem:(UIBarButtonItem *)barItem
                               sourceView:(UIView *)sourceView
{
    // Bind to the photo library only when already authorized/limited so
    // assetIdentifier can resolve to PHAsset (Live Photo pipeline). Otherwise
    // use an unbound config and consume NSItemProvider.
    PHPickerConfiguration *config = nil;
    if ([Utils isPhotoLibraryAccessible:[Utils photoLibraryAuthorizationStatus]]) {
        config = [[PHPickerConfiguration alloc] initWithPhotoLibrary:[PHPhotoLibrary sharedPhotoLibrary]];
    } else {
        config = [[PHPickerConfiguration alloc] init];
    }
    config.filter = [self pickerFilter];
    if (!self.allowsMultipleSelection) {
        config.selectionLimit = 1;
    } else if (self.maximumNumberOfSelection > 0) {
        config.selectionLimit = (NSInteger)self.maximumNumberOfSelection;
    } else {
        config.selectionLimit = 0; // unlimited
    }
    if (@available(iOS 15.0, *)) {
        config.selection = PHPickerConfigurationSelectionOrdered;
    }

    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:config];
    picker.delegate = self;

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
    }

    [vc presentViewController:picker animated:YES completion:nil];
}

- (NSString *)preferredTypeIdentifierForProvider:(NSItemProvider *)provider
{
    if (!provider) return nil;

    NSArray<NSString *> *preferred = nil;
    switch (self.mediaType) {
        case SeafImagePickerMediaTypeVideo:
            preferred = @[ UTTypeMovie.identifier, UTTypeVideo.identifier, UTTypeAudiovisualContent.identifier ];
            break;
        case SeafImagePickerMediaTypeAny:
            preferred = @[ UTTypeImage.identifier, UTTypeMovie.identifier, UTTypeVideo.identifier,
                           UTTypeAudiovisualContent.identifier ];
            break;
        case SeafImagePickerMediaTypeImage:
        default:
            preferred = @[ UTTypeImage.identifier ];
            break;
    }

    for (NSString *typeId in preferred) {
        if ([provider hasItemConformingToTypeIdentifier:typeId]) {
            return typeId;
        }
    }
    return provider.registeredTypeIdentifiers.firstObject;
}

- (NSString *)uniqueDestinationPathInDirectory:(NSString *)dir suggestedName:(NSString *)suggestedName
{
    NSString *name = suggestedName.length > 0 ? suggestedName : @"media";
    NSString *base = name.stringByDeletingPathExtension;
    NSString *ext = name.pathExtension;
    NSString *candidate = [dir stringByAppendingPathComponent:name];
    if (![[NSFileManager defaultManager] fileExistsAtPath:candidate]) {
        return candidate;
    }
    for (NSInteger i = 1; i < 1000; i++) {
        NSString *numbered = ext.length > 0
            ? [NSString stringWithFormat:@"%@ (%ld).%@", base, (long)i, ext]
            : [NSString stringWithFormat:@"%@ (%ld)", base, (long)i];
        candidate = [dir stringByAppendingPathComponent:numbered];
        if (![[NSFileManager defaultManager] fileExistsAtPath:candidate]) {
            return candidate;
        }
    }
    NSString *uuidName = ext.length > 0
        ? [NSString stringWithFormat:@"%@_%@.%@", base, NSUUID.UUID.UUIDString, ext]
        : [NSString stringWithFormat:@"%@_%@", base, NSUUID.UUID.UUIDString];
    return [dir stringByAppendingPathComponent:uuidName];
}

/// Copy provider content into `dir`. Must copy before the load callback returns.
- (void)materializeProvider:(NSItemProvider *)provider
                intoDirectory:(NSString *)dir
                   completion:(void (^)(NSURL * _Nullable fileURL))completion
{
    NSString *typeId = [self preferredTypeIdentifierForProvider:provider];
    if (!typeId) {
        if (completion) completion(nil);
        return;
    }

    __weak typeof(self) weakSelf = self;
    [provider loadFileRepresentationForTypeIdentifier:typeId
                                     completionHandler:^(NSURL * _Nullable url, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            if (completion) completion(nil);
            return;
        }
        if (url) {
            NSString *destPath = [strongSelf uniqueDestinationPathInDirectory:dir
                                                                suggestedName:url.lastPathComponent];
            NSError *copyError = nil;
            BOOL ok = [[NSFileManager defaultManager] copyItemAtURL:url
                                                              toURL:[NSURL fileURLWithPath:destPath]
                                                              error:&copyError];
            if (ok) {
                if (completion) completion([NSURL fileURLWithPath:destPath]);
                return;
            }
            Warning("PHPicker file copy failed: %@", copyError);
        } else if (error) {
            Warning("PHPicker loadFileRepresentation failed: %@", error);
        }

        // Fallback: data representation (still images / some providers).
        [provider loadDataRepresentationForTypeIdentifier:typeId
                                        completionHandler:^(NSData * _Nullable data, NSError * _Nullable dataError) {
            __strong typeof(weakSelf) innerSelf = weakSelf;
            if (!innerSelf || !data.length) {
                Warning("PHPicker loadDataRepresentation failed: %@", dataError);
                if (completion) completion(nil);
                return;
            }
            NSString *ext = @"bin";
            UTType *ut = [UTType typeWithIdentifier:typeId];
            if (ut.preferredFilenameExtension.length > 0) {
                ext = ut.preferredFilenameExtension;
            } else if ([typeId hasPrefix:@"public.image"] || [typeId isEqualToString:UTTypeImage.identifier]) {
                ext = @"jpg";
            } else if ([typeId hasPrefix:@"public.movie"] || [typeId isEqualToString:UTTypeMovie.identifier]) {
                ext = @"mov";
            }
            NSString *suggested = [NSString stringWithFormat:@"IMG_%@.%@", NSUUID.UUID.UUIDString, ext];
            NSString *destPath = [innerSelf uniqueDestinationPathInDirectory:dir suggestedName:suggested];
            BOOL written = [data writeToFile:destPath atomically:YES];
            if (completion) completion(written ? [NSURL fileURLWithPath:destPath] : nil);
        }];
    }];
}

- (void)processPickerResults:(NSArray<PHPickerResult *> *)results
{
    NSString *tmpdir = [SeafStorage uniqueDirUnder:SeafStorage.sharedObject.tempDir];
    if (![Utils checkMakeDir:tmpdir]) {
        Warning("Failed to create temp dir for PHPicker materialization");
        if ([self.delegate respondsToSelector:@selector(imagePickerHelper:didFailWithMessage:)]) {
            [self.delegate imagePickerHelper:self
                           didFailWithMessage:NSLocalizedString(@"Failed to load selected photos", @"Seafile")];
        }
        return;
    }

    BOOL libraryOK = [Utils isPhotoLibraryAccessible:[Utils photoLibraryAuthorizationStatus]];
    NSMutableArray<NSString *> *assetIds = [NSMutableArray array];
    NSMutableDictionary<NSString *, PHPickerResult *> *resultByAssetId = [NSMutableDictionary dictionary];
    NSMutableArray<PHPickerResult *> *providerOnly = [NSMutableArray array];

    for (PHPickerResult *result in results) {
        if (libraryOK && result.assetIdentifier.length > 0) {
            [assetIds addObject:result.assetIdentifier];
            resultByAssetId[result.assetIdentifier] = result;
        } else {
            [providerOnly addObject:result];
        }
    }

    NSMutableArray<PHAsset *> *assets = [NSMutableArray array];
    if (assetIds.count > 0) {
        PHFetchResult<PHAsset *> *fetch = [PHAsset fetchAssetsWithLocalIdentifiers:assetIds options:nil];
        NSMutableDictionary<NSString *, PHAsset *> *byId = [NSMutableDictionary dictionaryWithCapacity:fetch.count];
        [fetch enumerateObjectsUsingBlock:^(PHAsset *asset, NSUInteger idx, BOOL *stop) {
            if (asset.localIdentifier) {
                byId[asset.localIdentifier] = asset;
            }
        }];
        for (NSString *identifier in assetIds) {
            PHAsset *asset = byId[identifier];
            if (asset) {
                [assets addObject:asset];
            } else {
                PHPickerResult *fallback = resultByAssetId[identifier];
                if (fallback) {
                    Warning("PHPicker assetIdentifier not found in library, falling back to provider: %@", identifier);
                    [providerOnly addObject:fallback];
                }
            }
        }
    }

    if (providerOnly.count == 0) {
        [self deliverAssets:assets fileURLs:@[] failedCount:0 totalCount:results.count];
        return;
    }

    [SVProgressHUD showWithStatus:NSLocalizedString(@"Preparing files …", @"Seafile")];

    dispatch_group_t group = dispatch_group_create();
    NSMutableArray<NSURL *> *fileURLs = [NSMutableArray array];
    NSObject *lock = [NSObject new];
    __block NSUInteger providerFailures = 0;

    for (PHPickerResult *result in providerOnly) {
        dispatch_group_enter(group);
        [self materializeProvider:result.itemProvider intoDirectory:tmpdir completion:^(NSURL *fileURL) {
            @synchronized (lock) {
                if (fileURL) {
                    [fileURLs addObject:fileURL];
                } else {
                    providerFailures++;
                }
            }
            dispatch_group_leave(group);
        }];
    }

    __weak typeof(self) weakSelf = self;
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [SVProgressHUD dismiss];
        if (!strongSelf) return;
        [strongSelf deliverAssets:assets
                         fileURLs:[fileURLs copy]
                      failedCount:providerFailures
                       totalCount:results.count];
    });
}

- (void)deliverAssets:(NSArray<PHAsset *> *)assets
             fileURLs:(NSArray<NSURL *> *)fileURLs
          failedCount:(NSUInteger)failedCount
           totalCount:(NSUInteger)totalCount
{
    BOOL hasSuccess = assets.count > 0 || fileURLs.count > 0;

    if (!hasSuccess) {
        if ([self.delegate respondsToSelector:@selector(imagePickerHelper:didFailWithMessage:)]) {
            [self.delegate imagePickerHelper:self
                           didFailWithMessage:NSLocalizedString(@"Failed to load selected photos", @"Seafile")];
        } else if ([self.delegate respondsToSelector:@selector(imagePickerHelperDidCancel:)]) {
            // Last-resort fallback for delegates that only handle cancel.
            [self.delegate imagePickerHelperDidCancel:self];
        }
        return;
    }

    // Prefer a single combined callback so delegates (e.g. SDoc) can merge both
    // sources into one upload instead of racing two separate finish callbacks.
    if ([self.delegate respondsToSelector:@selector(imagePickerHelper:didFinishPickingAssets:fileURLs:)]) {
        [self.delegate imagePickerHelper:self
                  didFinishPickingAssets:assets ?: @[]
                                fileURLs:fileURLs ?: @[]];
    } else {
        if (assets.count > 0 &&
            [self.delegate respondsToSelector:@selector(imagePickerHelper:didFinishPickingAssets:)]) {
            [self.delegate imagePickerHelper:self didFinishPickingAssets:assets];
        }

        if (fileURLs.count > 0) {
            if ([self.delegate respondsToSelector:@selector(imagePickerHelper:didFinishPickingFileURLs:)]) {
                [self.delegate imagePickerHelper:self didFinishPickingFileURLs:fileURLs];
            } else if (assets.count == 0 &&
                       [self.delegate respondsToSelector:@selector(imagePickerHelper:didFailWithMessage:)]) {
                [self.delegate imagePickerHelper:self
                               didFailWithMessage:NSLocalizedString(@"Failed to load selected photos", @"Seafile")];
                return;
            }
        }
    }

    if (failedCount > 0 &&
        [self.delegate respondsToSelector:@selector(imagePickerHelper:didFailWithMessage:)]) {
        NSString *message = [NSString stringWithFormat:
                             NSLocalizedString(@"Failed to load %lu of %lu selected items", @"Seafile"),
                             (unsigned long)failedCount, (unsigned long)totalCount];
        [self.delegate imagePickerHelper:self didFailWithMessage:message];
    }
}

#pragma mark - PHPickerViewControllerDelegate

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results
{
    UIViewController *vc = self.presentingVC;
    __weak typeof(self) weakSelf = self;
    void (^finish)(void) = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        if (results.count == 0) {
            if ([strongSelf.delegate respondsToSelector:@selector(imagePickerHelperDidCancel:)]) {
                [strongSelf.delegate imagePickerHelperDidCancel:strongSelf];
            }
            return;
        }

        [strongSelf processPickerResults:results];
    };

    if (vc.presentedViewController == picker || picker.presentingViewController) {
        [picker dismissViewControllerAnimated:YES completion:finish];
    } else {
        finish();
    }
}

@end
